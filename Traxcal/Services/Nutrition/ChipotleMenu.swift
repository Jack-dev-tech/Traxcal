import Foundation

/// Ingredient-level Chipotle menu used by the bowl/burrito builder.
struct ChipotleMenu: Decodable, Sendable {
    struct Entree: Decodable, Identifiable, Hashable, Sendable {
        var id: String
        var name: String
        var symbol: String
        var base: String?
    }

    struct Ingredient: Decodable, Identifiable, Hashable, Sendable {
        var id: String
        var name: String
        var nutrients: Nutrients

        enum CodingKeys: String, CodingKey { case id, name, n }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            name = try c.decode(String.self, forKey: .name)
            nutrients = Nutrients(array: try c.decode([Double].self, forKey: .n))
        }
    }

    struct Category: Decodable, Identifiable, Hashable, Sendable {
        var id: String
        var name: String
        var hidden: Bool?
        var items: [Ingredient]
    }

    struct Preset: Decodable, Hashable, Sendable {
        var name: String
        var entree: String
        var items: [String]
    }

    /// Chipotle portions: light ≈ half, extra ≈ 1.5×, double = 2× (double protein is charged).
    enum Portion: String, CaseIterable, Identifiable, Codable, Sendable {
        case light, normal, extra, double
        var id: String { rawValue }
        var multiplier: Double {
            switch self {
            case .light: 0.5
            case .normal: 1
            case .extra: 1.5
            case .double: 2
            }
        }
        var title: String { rawValue.capitalized }
    }

    var entrees: [Entree]
    var categories: [Category]
    var presets: [Preset]

    static func load(bundle: Bundle = .main) -> ChipotleMenu? {
        guard let url = bundle.url(forResource: "chipotle", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ChipotleMenu.self, from: data)
    }

    func ingredient(_ id: String) -> Ingredient? {
        for category in categories {
            if let match = category.items.first(where: { $0.id == id }) { return match }
        }
        return nil
    }

    var visibleCategories: [Category] { categories.filter { $0.hidden != true } }

    /// Totals for an entrée plus selected ingredients with their portions.
    func total(entree: Entree, baseOverride: String? = nil, selections: [String: Portion]) -> Nutrients {
        var sum = Nutrients.zero
        if let baseID = baseOverride ?? entree.base, let base = ingredient(baseID) {
            sum += base.nutrients
        }
        for (id, portion) in selections {
            if let ing = ingredient(id) { sum += ing.nutrients.scaled(by: portion.multiplier) }
        }
        return sum
    }

    /// Popular orders exposed to universal search ("chipotle chicken bowl").
    func presetItems() -> [FoodItem] {
        presets.compactMap { preset in
            guard let entree = entrees.first(where: { $0.id == preset.entree }) else { return nil }
            var selections: [String: Portion] = [:]
            for id in preset.items {
                // Repeated ingredient ids in a preset mean a double portion.
                selections[id] = selections[id] == nil ? .normal : .double
            }
            let names = preset.items.compactMap { ingredient($0)?.name }
            return FoodItem(
                id: "chipotle-\(preset.name)".slug, name: preset.name, brand: "Chipotle",
                source: .chipotle, servingDescription: "1 \(entree.name.lowercased())", servingGrams: nil,
                nutrients: total(entree: entree, selections: selections),
                keywords: ["chipotle mexican grill", entree.name] + names
            )
        }
    }
}
