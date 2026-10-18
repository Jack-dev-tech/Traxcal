import Foundation

/// Where a food came from. Drives badges in search and ranking priority.
enum FoodSource: String, Codable, CaseIterable, Sendable {
    case usda, openFoodFacts, restaurant, chipotle, generic, custom, ai, barcode

    var label: String {
        switch self {
        case .usda: "USDA"
        case .openFoodFacts: "Open Food Facts"
        case .restaurant: "Restaurant"
        case .chipotle: "Chipotle Builder"
        case .generic: "Common Food"
        case .custom: "Custom"
        case .ai: "AI Estimate"
        case .barcode: "Barcode"
        }
    }

    var symbol: String {
        switch self {
        case .usda: "leaf.fill"
        case .openFoodFacts: "barcode"
        case .restaurant: "fork.knife"
        case .chipotle: "flame.fill"
        case .generic: "carrot.fill"
        case .custom: "pencil"
        case .ai: "sparkles"
        case .barcode: "barcode.viewfinder"
        }
    }
}

/// A selectable portion. `multiplier` is relative to the item's base serving.
struct ServingOption: Codable, Hashable, Sendable, Identifiable {
    var label: String
    var multiplier: Double
    var grams: Double?
    var id: String { label }
}

/// A food as returned by search or analysis; nutrients are for one base serving.
struct FoodItem: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var name: String
    var brand: String?
    var source: FoodSource
    var servingDescription: String
    var servingGrams: Double?
    var nutrients: Nutrients
    var servingOptions: [ServingOption] = []
    var barcode: String? = nil
    /// Extra searchable terms (aliases such as "mcd" or "big mac").
    var keywords: [String] = []

    var displayName: String {
        if let brand, !brand.isEmpty, !name.localizedCaseInsensitiveContains(brand) {
            return "\(brand) \(name)"
        }
        return name
    }

    /// Serving choices shown in the detail sheet; always includes the base serving.
    var allServingOptions: [ServingOption] {
        var options = [ServingOption(label: servingDescription, multiplier: 1, grams: servingGrams)]
        options.append(contentsOf: servingOptions.filter { $0.label != servingDescription })
        if let g = servingGrams, g > 0, !options.contains(where: { $0.label == "100 g" }) {
            options.append(ServingOption(label: "100 g", multiplier: 100 / g, grams: 100))
            options.append(ServingOption(label: "1 oz", multiplier: 28.35 / g, grams: 28.35))
        }
        return options
    }
}

enum MealType: String, Codable, CaseIterable, Identifiable, Sendable {
    case breakfast, lunch, dinner, snack

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .breakfast: "sunrise.fill"
        case .lunch: "sun.max.fill"
        case .dinner: "moon.stars.fill"
        case .snack: "carrot.fill"
        }
    }

    /// Best guess for a meal based on the time of day.
    static func suggested(for date: Date = .now) -> MealType {
        switch Calendar.current.component(.hour, from: date) {
        case 4..<11: .breakfast
        case 11..<15: .lunch
        case 15..<17: .snack
        case 17..<22: .dinner
        default: .snack
        }
    }
}
