import Foundation

/// Open Food Facts: free, no key. Great for packaged foods and barcode lookups.
struct OpenFoodFactsProvider: Sendable {
    private static let userAgent = "Traxcal/1.0 (iOS; https://github.com/jack-dev-tech/traxcal)"
    private static let fields = "code,product_name,brands,nutriments,serving_size,serving_quantity"

    func search(_ query: String) async throws -> [FoodItem] {
        var components = URLComponents(string: "https://world.openfoodfacts.org/cgi/search.pl")!
        components.queryItems = [
            URLQueryItem(name: "search_terms", value: query),
            URLQueryItem(name: "search_simple", value: "1"),
            URLQueryItem(name: "action", value: "process"),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "page_size", value: "20"),
            URLQueryItem(name: "fields", value: Self.fields),
        ]
        let response: SearchResponse = try await fetch(components.url!)
        return response.products.compactMap { Self.item(from: $0, source: .openFoodFacts) }
    }

    func lookup(barcode: String) async throws -> FoodItem? {
        let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(barcode).json?fields=\(Self.fields)")!
        let response: ProductResponse = try await fetch(url)
        guard let product = response.product else { return nil }
        var item = Self.item(from: product, source: .barcode)
        item?.barcode = barcode
        return item
    }

    private func fetch<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(T.self, from: data)
    }

    struct SearchResponse: Decodable { var products: [Product] }
    struct ProductResponse: Decodable { var product: Product? }

    struct Product: Decodable {
        var code: String?
        var product_name: String?
        var brands: String?
        var serving_size: String?
        var serving_quantity: FlexibleDouble?
        var nutriments: [String: FlexibleDouble]?
    }

    static func item(from product: Product, source: FoodSource) -> FoodItem? {
        guard let name = product.product_name?.trimmingCharacters(in: .whitespaces), !name.isEmpty,
              let n = product.nutriments,
              let kcal100 = n["energy-kcal_100g"]?.value ?? n["energy_100g"]?.value.map({ $0 / 4.184 })
        else { return nil }

        func g(_ key: String) -> Double? { n["\(key)_100g"]?.value }
        func mg(_ key: String) -> Double? { g(key).map { $0 * 1000 } }

        let per100 = Nutrients(
            calories: kcal100, protein: g("proteins") ?? 0, carbs: g("carbohydrates") ?? 0, fat: g("fat") ?? 0,
            fiber: g("fiber"), sugar: g("sugars"), saturatedFat: g("saturated-fat"),
            cholesterol: mg("cholesterol"), sodium: mg("sodium"), potassium: mg("potassium"),
            calcium: mg("calcium"), iron: mg("iron"), vitaminC: mg("vitamin-c"),
            vitaminD: g("vitamin-d").map { $0 * 1_000_000 }, caffeine: mg("caffeine")
        )

        let servingGrams = product.serving_quantity?.value.flatMap { $0 > 0 ? $0 : nil }
        let grams = servingGrams ?? 100
        let servingText = servingGrams != nil ? (product.serving_size ?? "\(Int(grams)) g") : "100 g"
        let brand = product.brands?.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) }

        return FoodItem(
            id: "off-\(product.code ?? name.slug)", name: name, brand: brand, source: source,
            servingDescription: servingText, servingGrams: grams, nutrients: per100.scaled(by: grams / 100),
            barcode: product.code
        )
    }
}

/// Open Food Facts mixes numbers and numeric strings; accept both.
struct FlexibleDouble: Decodable, Sendable {
    var value: Double?

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) { value = d }
        else if let s = try? c.decode(String.self) { value = Double(s.replacingOccurrences(of: ",", with: ".")) }
        else { value = nil }
    }
}
