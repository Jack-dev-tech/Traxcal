import Foundation
import Observation
import SwiftData
import WidgetKit

/// Single entry point for creating, editing and deleting log entries so every change
/// is mirrored to Apple Health and the Home Screen widgets.
@MainActor
@Observable
final class FoodLogger {
    let context: ModelContext
    let goals: GoalStore
    private let health = HealthKitService.shared
    /// Bumped on every change so dashboards can animate.
    private(set) var changeCount = 0

    init(context: ModelContext, goals: GoalStore) {
        self.context = context
        self.goals = goals
    }

    @discardableResult
    func log(_ item: FoodItem, servings: Double, meal: MealType, date: Date = .now, photo: Data? = nil) -> FoodEntry {
        let entry = FoodEntry(item: item, servings: servings, meal: meal, date: date, photo: photo)
        context.insert(entry)
        commit()
        Task { await health.save(entry); try? context.save() }
        return entry
    }

    /// Call after mutating an entry's fields in an edit sheet.
    func didEdit(_ entry: FoodEntry) {
        entry.revision += 1
        commit()
        Task { await health.save(entry); try? context.save() }
    }

    func delete(_ entry: FoodEntry) {
        let id = entry.id
        context.delete(entry)
        commit()
        Task { await health.delete(entryID: id) }
    }

    func duplicate(_ entry: FoodEntry, to date: Date = .now) {
        log(entry.asFoodItem, servings: entry.servings, meal: MealType.suggested(for: date), date: date)
    }

    func toggleFavorite(_ item: FoodItem) {
        let key = item.id
        let descriptor = FetchDescriptor<FavoriteFood>(predicate: #Predicate { $0.key == key })
        if let existing = try? context.fetch(descriptor).first {
            context.delete(existing)
        } else {
            context.insert(FavoriteFood(item: item))
        }
        try? context.save()
    }

    func isFavorite(_ item: FoodItem) -> Bool {
        let key = item.id
        let descriptor = FetchDescriptor<FavoriteFood>(predicate: #Predicate { $0.key == key })
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
    }

    func addWater(_ ml: Double) {
        WaterStore.add(ml)
        syncPendingWater()
        refreshWidgets()
    }

    /// Mirrors water logged from the widget to Apple Health.
    func syncPendingWater() {
        let pending = WaterStore.drainPendingHealthWrites()
        changeCount += 1
        guard !pending.isEmpty else { return }
        // Negative amounts are undo taps; Health samples can't be negative, so remove the last one instead.
        Task {
            for write in pending {
                if write.milliliters > 0 {
                    await health.saveWater(milliliters: write.milliliters, date: write.date)
                } else {
                    await health.removeLastWater(on: write.date)
                }
            }
        }
    }

    /// Writes entries that never reached Apple Health: a failed save, or logged while Health was off.
    func syncUnsyncedToHealth() {
        guard health.isEnabled else { return }
        var descriptor = FetchDescriptor<FoodEntry>(predicate: #Predicate { !$0.syncedToHealth })
        descriptor.fetchLimit = 200
        let pending = (try? context.fetch(descriptor)) ?? []
        guard !pending.isEmpty else { return }
        Task {
            for entry in pending { await health.save(entry) }
            try? context.save()
        }
    }

    private func commit() {
        try? context.save()
        changeCount += 1
        refreshWidgets()
    }

    // MARK: Queries

    func entries(from start: Date, to end: Date) -> [FoodEntry] {
        let descriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.date >= start && $0.date < end },
            sortBy: [SortDescriptor(\.date)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func entries(on day: Date) -> [FoodEntry] { entries(from: day.startOfDay, to: day.endOfDay) }

    func recentItems(limit: Int = 12) -> [FoodItem] {
        var descriptor = FetchDescriptor<FoodEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 80
        let recent = (try? context.fetch(descriptor)) ?? []
        var seen = Set<String>()
        return recent.compactMap { entry in
            seen.insert(entry.displayName).inserted ? entry.asFoodItem : nil
        }
        .prefix(limit)
        .map { $0 }
    }

    // MARK: Widgets

    func refreshWidgets(insight: String? = nil) {
        let today = entries(on: .now).map(\.total).sum()
        let week: [WidgetSnapshot.Day] = (0..<7).map { offset in
            let day = Date.now.adding(days: offset - 6).startOfDay
            return WidgetSnapshot.Day(date: day, calories: entries(on: day).map(\.total.calories).reduce(0, +))
        }
        let previous = WidgetSnapshotStore.load()
        let snapshot = WidgetSnapshot(
            updatedAt: .now, calories: today.calories, calorieGoal: goals.goal(.calories),
            protein: today.protein, proteinGoal: goals.goal(.protein),
            carbs: today.carbs, carbsGoal: goals.goal(.carbs),
            fat: today.fat, fatGoal: goals.goal(.fat),
            waterML: WaterStore.amount(), waterGoalML: goals.waterGoalML,
            lastFoodName: entries(on: .now).last?.displayName,
            insight: insight ?? previous?.insight,
            week: week
        )
        WidgetSnapshotStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
