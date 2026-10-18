import Foundation
import HealthKit
import Observation

/// Writes logged food to Apple Health as food correlations and reads activity/weight.
/// Each entry is tagged with its UUID as the HealthKit sync identifier, so saving an edited
/// entry with a higher revision replaces the old samples instead of duplicating them.
@Observable
@MainActor
final class HealthKitService {
    static let shared = HealthKitService()

    private let store = HKHealthStore()
    var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "health.enabled") }
    }
    private(set) var activeEnergyToday: Double = 0
    private(set) var latestWeightKg: Double?

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: "health.enabled")
    }

    private static let nutrientTypes: [(NutrientKind, HKQuantityTypeIdentifier, HKUnit)] = [
        (.calories, .dietaryEnergyConsumed, .kilocalorie()),
        (.protein, .dietaryProtein, .gram()),
        (.carbs, .dietaryCarbohydrates, .gram()),
        (.fat, .dietaryFatTotal, .gram()),
        (.fiber, .dietaryFiber, .gram()),
        (.sugar, .dietarySugar, .gram()),
        (.saturatedFat, .dietaryFatSaturated, .gram()),
        (.cholesterol, .dietaryCholesterol, .gramUnit(with: .milli)),
        (.sodium, .dietarySodium, .gramUnit(with: .milli)),
        (.potassium, .dietaryPotassium, .gramUnit(with: .milli)),
        (.calcium, .dietaryCalcium, .gramUnit(with: .milli)),
        (.iron, .dietaryIron, .gramUnit(with: .milli)),
        (.vitaminC, .dietaryVitaminC, .gramUnit(with: .milli)),
        (.vitaminD, .dietaryVitaminD, .gramUnit(with: .micro)),
        (.caffeine, .dietaryCaffeine, .gramUnit(with: .milli)),
    ]

    private var shareTypes: Set<HKSampleType> {
        var set = Set<HKSampleType>(Self.nutrientTypes.map { HKQuantityType($0.1) as HKSampleType })
        set.insert(HKQuantityType(.dietaryWater))
        return set
    }

    private var readTypes: Set<HKObjectType> {
        var set = Set<HKObjectType>(shareTypes.map { $0 as HKObjectType })
        set.insert(HKQuantityType(.activeEnergyBurned))
        set.insert(HKQuantityType(.bodyMass))
        set.insert(HKQuantityType(.height))
        return set
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        guard Self.isAvailable else { return false }
        do {
            try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
            isEnabled = true
            await refreshReadings()
            return true
        } catch {
            return false
        }
    }

    // MARK: Writing

    func save(_ entry: FoodEntry) async {
        guard isEnabled, Self.isAvailable else { return }
        let total = entry.total
        let metadata: [String: Any] = [
            HKMetadataKeyFoodType: entry.displayName,
            HKMetadataKeySyncIdentifier: entry.id.uuidString,
            HKMetadataKeySyncVersion: entry.revision,
            "TraxcalMeal": entry.meal.rawValue,
        ]
        var samples = Set<HKSample>()
        for (kind, identifier, unit) in Self.nutrientTypes {
            guard let value = total.value(kind), value > 0 else { continue }
            let type = HKQuantityType(identifier)
            guard store.authorizationStatus(for: type) == .sharingAuthorized else { continue }
            samples.insert(HKQuantitySample(
                type: type, quantity: HKQuantity(unit: unit, doubleValue: value),
                start: entry.date, end: entry.date,
                metadata: [HKMetadataKeyFoodType: entry.displayName]
            ))
        }
        // A replaced correlation leaves its old child samples; remove them first on edits,
        // including edits that zero everything out and so have nothing new to write.
        if entry.revision > 1 { await delete(entryID: entry.id) }
        guard !samples.isEmpty else { return }
        let correlation = HKCorrelation(
            type: HKCorrelationType(.food), start: entry.date, end: entry.date,
            objects: samples, metadata: metadata
        )
        do {
            try await store.save(correlation)
            entry.syncedToHealth = true
        } catch {
            entry.syncedToHealth = false
        }
    }

    func delete(entryID: UUID) async {
        guard isEnabled, Self.isAvailable else { return }
        let predicate = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncIdentifier, allowedValues: [entryID.uuidString])
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.correlation(type: HKCorrelationType(.food), predicate: predicate)],
            sortDescriptors: []
        )
        guard let correlations = try? await descriptor.result(for: store), !correlations.isEmpty else { return }
        var objects: [HKObject] = []
        for c in correlations {
            objects.append(c)
            objects.append(contentsOf: c.objects)
        }
        try? await store.delete(objects)
    }

    func saveWater(milliliters: Double, date: Date = .now) async {
        guard isEnabled, Self.isAvailable, milliliters > 0 else { return }
        let sample = HKQuantitySample(
            type: HKQuantityType(.dietaryWater),
            quantity: HKQuantity(unit: .literUnit(with: .milli), doubleValue: milliliters),
            start: date, end: date
        )
        try? await store.save(sample)
    }

    /// Undo for a water tap: deletes Traxcal's most recent water sample on that day.
    func removeLastWater(on date: Date) async {
        guard isEnabled, Self.isAvailable else { return }
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForSamples(withStart: date.startOfDay, end: date.endOfDay),
            HKQuery.predicateForObjects(from: HKSource.default()),
        ])
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.dietaryWater), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)], limit: 1
        )
        guard let last = try? await descriptor.result(for: store).first else { return }
        try? await store.delete(last)
    }

    // MARK: Reading

    func refreshReadings() async {
        guard isEnabled, Self.isAvailable else { return }
        let today = HKQuery.predicateForSamples(withStart: Date.now.startOfDay, end: .now)
        let energy = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(.activeEnergyBurned), predicate: today),
            options: .cumulativeSum
        )
        activeEnergyToday = (try? await energy.result(for: store))?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0

        let weight = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.bodyMass))],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)], limit: 1
        )
        latestWeightKg = (try? await weight.result(for: store))?.first?.quantity.doubleValue(for: .gramUnit(with: .kilo))
    }
}
