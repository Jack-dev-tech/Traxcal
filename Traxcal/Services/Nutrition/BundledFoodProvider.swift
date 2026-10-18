import Foundation

/// Offline restaurant + common-food database shipped in the app bundle.
final class BundledFoodProvider: @unchecked Sendable {
    static let shared = BundledFoodProvider()

    private(set) var items: [FoodItem] = []
    let chipotle: ChipotleMenu?

    init(bundle: Bundle = .main) {
        chipotle = ChipotleMenu.load(bundle: bundle)
        var all: [FoodItem] = []
        all += Self.loadRestaurants(bundle: bundle)
        all += Self.loadGeneric(bundle: bundle)
        if let chipotle { all += chipotle.presetItems() }
        items = all
    }

    // MARK: Search

    func search(_ query: String, limit: Int = 40) -> [FoodItem] {
        let tokens = SearchText.tokens(query)
        guard !tokens.isEmpty else { return [] }
        return items
            .compactMap { item -> (FoodItem, Double)? in
                let score = SearchText.score(tokens: tokens, query: query, item: item)
                return score > 0 ? (item, score) : nil
            }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    // MARK: Loading

    private struct RestaurantFile: Decodable {
        struct Brand: Decodable {
            var name: String
            var aliases: [String]
            var items: [Row]
        }
        var brands: [Brand]
    }

    private struct GenericFile: Decodable {
        struct Category: Decodable {
            var name: String
            var items: [Row]
        }
        var categories: [Category]
    }

    /// `[name, serving, grams, [cal, p, c, f, fiber, sugar, satFat, sodium, caffeine?]]`
    struct Row: Decodable {
        var name: String
        var serving: String
        var grams: Double?
        var nutrients: Nutrients

        init(from decoder: Decoder) throws {
            var c = try decoder.unkeyedContainer()
            name = try c.decode(String.self)
            serving = try c.decode(String.self)
            grams = try c.decodeIfPresent(Double.self)
            nutrients = Nutrients(array: try c.decode([Double].self))
        }
    }

    private static func loadRestaurants(bundle: Bundle) -> [FoodItem] {
        guard let url = bundle.url(forResource: "restaurants", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(RestaurantFile.self, from: data) else { return [] }
        return file.brands.flatMap { brand in
            brand.items.map { row in
                FoodItem(
                    id: "rest-\(brand.name)-\(row.name)".slug, name: row.name, brand: brand.name,
                    source: .restaurant, servingDescription: row.serving, servingGrams: row.grams,
                    nutrients: row.nutrients, keywords: brand.aliases
                )
            }
        }
    }

    private static func loadGeneric(bundle: Bundle) -> [FoodItem] {
        guard let url = bundle.url(forResource: "generic_foods", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(GenericFile.self, from: data) else { return [] }
        return file.categories.flatMap { category in
            category.items.map { row in
                FoodItem(
                    id: "gen-\(row.name)".slug, name: row.name, brand: nil, source: .generic,
                    servingDescription: row.serving, servingGrams: row.grams,
                    nutrients: row.nutrients, keywords: [category.name]
                )
            }
        }
    }
}

extension Nutrients {
    /// Builds nutrients from the compact dataset array format.
    init(array n: [Double]) {
        func at(_ i: Int) -> Double? { i < n.count ? n[i] : nil }
        self.init(
            calories: at(0) ?? 0, protein: at(1) ?? 0, carbs: at(2) ?? 0, fat: at(3) ?? 0,
            fiber: at(4), sugar: at(5), saturatedFat: at(6), sodium: at(7), caffeine: at(8)
        )
    }
}

extension String {
    var slug: String {
        lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
            .map { $0.isLetter || $0.isNumber ? $0 : "-" }
            .reduce(into: "") { $0.append($1) }
    }
}

/// Text normalization + relevance scoring shared by all providers.
enum SearchText {
    static func normalize(_ s: String) -> String {
        s.lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "’", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "&", with: " and ")
    }

    private static let stopWords: Set<String> = ["a", "an", "the", "of", "with", "and", "from", "at", "in"]

    static func tokens(_ s: String) -> [String] {
        normalize(s)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { !stopWords.contains($0) }
    }

    /// Scores 0...~10. Every query token must match (prefix or fuzzy) somewhere in the
    /// name, brand or aliases, so "chipotle chicken" or "mcd nuggets" both resolve.
    static func score(tokens: [String], query: String, item: FoodItem) -> Double {
        let nameTokens = Self.tokens(item.name)
        let brandTokens = Self.tokens(item.brand ?? "")
        let keywordTokens = item.keywords.flatMap { Self.tokens($0) }
        let haystack = nameTokens + brandTokens + keywordTokens
        let joinedBrand = brandTokens.joined()
        let joinedKeywords = item.keywords.map { normalize($0).replacingOccurrences(of: " ", with: "") }

        var total = 0.0
        for token in tokens {
            var best = 0.0
            for word in haystack {
                if word == token { best = max(best, 1.0) }
                else if word.hasPrefix(token) { best = max(best, 0.8) }
                else if token.count >= 4, word.count >= 4, editDistance(word, token) <= (token.count > 6 ? 2 : 1) { best = max(best, 0.6) }
            }
            // "mcdonalds" vs "mcdonald s", "innout" vs "in n out", etc.
            if token == joinedBrand || joinedKeywords.contains(token) { best = max(best, 1.0) }
            if best == 0 { return 0 }
            total += best
        }

        var score = total / Double(tokens.count) * 6
        let normalizedName = normalize(item.name)
        let normalizedQuery = normalize(query)
        if normalizedName == normalizedQuery { score += 3 }
        else if normalizedName.hasPrefix(normalizedQuery) { score += 1.5 }
        // Prefer items whose name matches over items matched only by brand.
        let nameHits = tokens.filter { t in nameTokens.contains { $0.hasPrefix(t) } }.count
        score += Double(nameHits) / Double(tokens.count) * 1.5
        // Shorter names are usually the "canonical" item.
        score -= Double(nameTokens.count) * 0.05
        return max(score, 0.01)
    }

    static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        for i in 1...a.count {
            var cur = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            prev = cur
        }
        return prev[b.count]
    }
}
