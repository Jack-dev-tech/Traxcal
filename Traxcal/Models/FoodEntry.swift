import Foundation
import SwiftData

/// A logged food. Nutrients are stored per serving so editing the serving count re-scales totals.
@Model
final class FoodEntry {
    @Attribute(.unique) var id: UUID
    var name: String
    var brand: String?
    var sourceRaw: String
    var mealRaw: String
    var date: Date
    var servings: Double
    var servingDescription: String
    var servingGrams: Double?
    var perServing: Nutrients
    var notes: String
    /// Incremented on each edit; used as the HealthKit sync version so edits replace old samples.
    var revision: Int
    var syncedToHealth: Bool
    @Attribute(.externalStorage) var photo: Data?

    init(
        id: UUID = UUID(), name: String, brand: String? = nil, source: FoodSource,
        meal: MealType, date: Date = .now, servings: Double = 1, servingDescription: String,
        servingGrams: Double? = nil, perServing: Nutrients, notes: String = "", photo: Data? = nil
    ) {
        self.id = id
        self.name = name
        self.brand = brand
        self.sourceRaw = source.rawValue
        self.mealRaw = meal.rawValue
        self.date = date
        self.servings = servings
        self.servingDescription = servingDescription
        self.servingGrams = servingGrams
        self.perServing = perServing
        self.notes = notes
        self.revision = 1
        self.syncedToHealth = false
        self.photo = photo
    }

    convenience init(item: FoodItem, servings: Double, meal: MealType, date: Date = .now, photo: Data? = nil) {
        self.init(
            name: item.name, brand: item.brand, source: item.source, meal: meal, date: date,
            servings: servings, servingDescription: item.servingDescription,
            servingGrams: item.servingGrams, perServing: item.nutrients, photo: photo
        )
    }

    var source: FoodSource { FoodSource(rawValue: sourceRaw) ?? .custom }

    var meal: MealType {
        get { MealType(rawValue: mealRaw) ?? .snack }
        set { mealRaw = newValue.rawValue }
    }

    var total: Nutrients { perServing.scaled(by: servings) }

    var displayName: String { asFoodItem.displayName }

    /// Re-create a search item from this entry (used for "log again" and favorites).
    var asFoodItem: FoodItem {
        FoodItem(
            id: "entry-\(name.lowercased())-\(brand ?? "")", name: name, brand: brand, source: source,
            servingDescription: servingDescription, servingGrams: servingGrams, nutrients: perServing
        )
    }
}

/// Foods the user starred for quick logging.
@Model
final class FavoriteFood {
    @Attribute(.unique) var key: String
    var item: FoodItem
    var addedAt: Date

    init(item: FoodItem) {
        self.key = item.id
        self.item = item
        self.addedAt = .now
    }
}

/// Cached AI insight cards, one record per day.
@Model
final class InsightRecord {
    @Attribute(.unique) var dayKey: String
    var createdAt: Date
    var insights: [Insight]
    var providerName: String

    init(dayKey: String, insights: [Insight], providerName: String) {
        self.dayKey = dayKey
        self.createdAt = .now
        self.insights = insights
        self.providerName = providerName
    }
}

struct Insight: Codable, Hashable, Identifiable, Sendable {
    enum Tone: String, Codable, Sendable { case positive, neutral, warning }
    var id = UUID()
    var title: String
    var detail: String
    var tone: Tone
    var symbol: String

    enum CodingKeys: String, CodingKey { case title, detail, tone, symbol }

    init(title: String, detail: String, tone: Tone, symbol: String) {
        self.title = title
        self.detail = detail
        self.tone = tone
        self.symbol = symbol
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decode(String.self, forKey: .title)
        detail = try c.decodeIfPresent(String.self, forKey: .detail) ?? ""
        tone = (try? c.decode(Tone.self, forKey: .tone)) ?? .neutral
        symbol = (try? c.decode(String.self, forKey: .symbol)) ?? "sparkles"
    }
}

extension Date {
    var dayKey: String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: self)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    var startOfDay: Date { Calendar.current.startOfDay(for: self) }
    var endOfDay: Date { Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)! }

    func adding(days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: self)!
    }
}
