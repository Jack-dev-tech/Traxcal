import Foundation

/// USDA FoodData Central search (free). Uses the user's key when set, otherwise `DEMO_KEY`,
/// which is rate limited but works out of the box. Includes branded and restaurant items.
struct USDAFoodDataProvider: Sendable {
    var apiKey: String

    static let nutrientMap: [String: NutrientKind] = [
        "208": .calories, "203": .protein, "205": .carbs, "204": .fat, "291": .fiber,
        "269": .sugar, "606": .saturatedFat, "601": .cholesterol, "307": .sodium,
        "306": .potassium, "301": .calcium, "303": .iron, "401": .vitaminC, "328": .vitaminD,
        "262": .caffeine,
    ]

    func search(_ query: String) async throws -> [FoodItem] {
        var components = URLComponents(string: "https://api.nal.usda.gov/fdc/v1/foods/search")!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey.isEmpty ? "DEMO_KEY" : apiKey),
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "pageSize", value: "25"),
            URLQueryItem(name: "dataType", value: "Branded,Survey (FNDDS),Foundation,SR Legacy"),
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 8
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
        return decoded.foods.compactMap(Self.item(from:))
    }

    struct SearchResponse: Decodable {
        var foods: [Food]
    }

    struct Food: Decodable {
        var fdcId: Int
        var description: String
        var dataType: String?
        var brandOwner: String?
        var brandName: String?
        var servingSize: Double?
        var servingSizeUnit: String?
        var householdServingFullText: String?
        var foodNutrients: [FoodNutrient]
    }

    struct FoodNutrient: Decodable {
        var nutrientNumber: String?
        var unitName: String?
        var value: Double?
    }

    static func item(from food: Food) -> FoodItem? {
        // Search results report nutrients per 100 g (or 100 ml).
        var per100 = Nutrients.zero
        var hasEnergy = false
        for n in food.foodNutrients {
            guard let number = n.nutrientNumber, let kind = nutrientMap[number], let value = n.value else { continue }
            if kind == .calories {
                guard n.unitName?.uppercased() == "KCAL" else { continue }
                hasEnergy = true
            }
            // FDC reports vitamin D (328) in µg and the rest in our units already.
            per100.set(kind, value)
        }
        guard hasEnergy else { return nil }

        let unit = food.servingSizeUnit?.lowercased() ?? ""
        let gramsPerServing: Double? = {
            guard let size = food.servingSize, size > 0 else { return nil }
            return ["g", "grm", "ml", "mlt"].contains(unit) ? size : nil
        }()
        let grams = gramsPerServing ?? 100
        let servingText: String = {
            if let household = food.householdServingFullText, !household.isEmpty, let g = gramsPerServing {
                return "\(household) (\(Int(g.rounded())) g)"
            }
            if let g = gramsPerServing { return "\(Int(g.rounded())) g" }
            return "100 g"
        }()

        let brand = (food.brandName?.isEmpty == false ? food.brandName : food.brandOwner)?.capitalizedBrand
        return FoodItem(
            id: "usda-\(food.fdcId)", name: food.description.capitalizedFoodName, brand: brand,
            source: .usda, servingDescription: servingText, servingGrams: grams,
            nutrients: per100.scaled(by: grams / 100)
        )
    }
}

extension String {
    /// USDA descriptions are often ALL CAPS; make them readable.
    var capitalizedFoodName: String {
        let letters = filter(\.isLetter)
        guard !letters.isEmpty, letters == letters.uppercased() else { return self }
        return lowercased().capitalized
    }

    var capitalizedBrand: String {
        let letters = filter(\.isLetter)
        guard letters == letters.uppercased() else { return self }
        return lowercased().capitalized
    }
}
