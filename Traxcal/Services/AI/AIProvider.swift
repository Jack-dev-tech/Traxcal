import Foundation
import UIKit

/// Result of analyzing a meal photo or description.
struct FoodAnalysis: Codable, Sendable, Equatable {
    struct Item: Codable, Sendable, Equatable, Identifiable {
        var id = UUID()
        var name: String
        var portion: String
        var grams: Double?
        var confidence: Double
        var nutrients: Nutrients

        enum CodingKeys: String, CodingKey {
            case name, portion, serving, grams, confidence, calories, protein, carbs, fat, fiber, sugar
            case saturatedFat, sodium, cholesterol, potassium
        }

        init(name: String, portion: String, grams: Double?, confidence: Double, nutrients: Nutrients) {
            self.name = name
            self.portion = portion
            self.grams = grams
            self.confidence = confidence
            self.nutrients = nutrients
        }

        /// Lenient decoding: models return numbers as strings, omit keys, or use "serving".
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            func num(_ key: CodingKeys) -> Double? {
                if let d = try? c.decode(Double.self, forKey: key) { return d }
                if let s = try? c.decode(String.self, forKey: key) {
                    let cleaned = s.filter { $0.isNumber || $0 == "." }
                    return Double(cleaned)
                }
                return nil
            }
            name = (try? c.decode(String.self, forKey: .name)) ?? "Food"
            portion = (try? c.decode(String.self, forKey: .portion)) ?? (try? c.decode(String.self, forKey: .serving)) ?? "1 serving"
            grams = num(.grams)
            confidence = min(max(num(.confidence) ?? 0.6, 0), 1)
            nutrients = Nutrients(
                calories: num(.calories) ?? 0, protein: num(.protein) ?? 0, carbs: num(.carbs) ?? 0,
                fat: num(.fat) ?? 0, fiber: num(.fiber), sugar: num(.sugar), saturatedFat: num(.saturatedFat),
                cholesterol: num(.cholesterol), sodium: num(.sodium), potassium: num(.potassium)
            )
            // If calories are missing or wildly inconsistent with macros, trust the macros.
            let macro = nutrients.macroCalories
            if nutrients.calories <= 0 || (macro > 0 && abs(macro - nutrients.calories) / macro > 0.6) {
                nutrients.calories = macro.rounded()
            }
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(name, forKey: .name)
            try c.encode(portion, forKey: .portion)
            try c.encodeIfPresent(grams, forKey: .grams)
            try c.encode(confidence, forKey: .confidence)
            try c.encode(nutrients.calories, forKey: .calories)
            try c.encode(nutrients.protein, forKey: .protein)
            try c.encode(nutrients.carbs, forKey: .carbs)
            try c.encode(nutrients.fat, forKey: .fat)
            try c.encodeIfPresent(nutrients.fiber, forKey: .fiber)
            try c.encodeIfPresent(nutrients.sugar, forKey: .sugar)
            try c.encodeIfPresent(nutrients.saturatedFat, forKey: .saturatedFat)
            try c.encodeIfPresent(nutrients.sodium, forKey: .sodium)
        }

        static func == (a: Item, b: Item) -> Bool { a.id == b.id && a.nutrients == b.nutrients && a.name == b.name }

        var asFoodItem: FoodItem {
            FoodItem(
                id: "ai-\(id.uuidString)", name: name, brand: nil, source: .ai,
                servingDescription: portion, servingGrams: grams, nutrients: nutrients
            )
        }
    }

    var items: [Item]
    var mealName: String?
    var notes: String?

    enum CodingKeys: String, CodingKey { case items, mealName, notes }

    init(items: [Item], mealName: String? = nil, notes: String? = nil) {
        self.items = items
        self.mealName = mealName
        self.notes = notes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = (try? c.decode([Item].self, forKey: .items)) ?? []
        mealName = try? c.decode(String.self, forKey: .mealName)
        notes = try? c.decode(String.self, forKey: .notes)
    }

    var total: Nutrients { items.map(\.nutrients).sum() }
}

enum AIError: LocalizedError {
    case notConfigured(String)
    case missingAPIKey(String)
    case visionUnsupported(String)
    case badResponse(String)
    case modelNotDownloaded
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured(let s): "AI isn't set up yet. \(s)"
        case .missingAPIKey(let p): "Add your \(p) API key in Settings → AI."
        case .visionUnsupported(let m): "\(m) can't read images. Pick a vision model or describe the meal instead."
        case .badResponse(let s): "The AI returned something unexpected. \(s)"
        case .modelNotDownloaded: "Download an on-device model in Settings → AI → On-Device Models."
        case .unavailable(let s): s
        }
    }
}

/// Every AI backend (cloud or on-device) implements this.
protocol AIProvider: Sendable {
    var displayName: String { get }
    var supportsVision: Bool { get }
    /// Sends a system + user prompt (optionally with a JPEG image) and returns raw text.
    func complete(system: String, user: String, imageJPEG: Data?, wantsJSON: Bool) async throws -> String
}

enum AIPrompts {
    static let foodSystem = """
    You are a registered dietitian and food-recognition expert inside a calorie tracking app.
    Identify every distinct food or drink, estimate realistic portion sizes, and estimate nutrition \
    for the portion shown. Use typical USDA values and known restaurant nutrition when a brand is recognizable.
    Respond with ONLY minified JSON, no prose, matching exactly:
    {"mealName":string,"items":[{"name":string,"portion":string,"grams":number,"confidence":number,\
    "calories":number,"protein":number,"carbs":number,"fat":number,"fiber":number,"sugar":number,\
    "saturatedFat":number,"sodium":number}],"notes":string}
    Units: grams for macros, milligrams for sodium, kcal for calories. confidence is 0-1.
    """

    static func photoUser(hint: String?) -> String {
        var s = "Analyze this meal photo and estimate its nutrition."
        if let hint, !hint.isEmpty { s += " The user adds: \(hint)" }
        return s
    }

    static func textUser(_ description: String) -> String {
        "Estimate the nutrition for what I ate: \(description)"
    }

    static func labelsUser(labels: [String], hint: String?) -> String {
        var s = "An on-device image classifier saw these items in a meal photo (most confident first): \(labels.joined(separator: ", ")). Estimate a typical single-person portion and its nutrition."
        if let hint, !hint.isEmpty { s += " The user adds: \(hint)" }
        return s
    }

    static let insightsSystem = """
    You are an encouraging, evidence-based nutrition coach. Given a user's goals and recent intake stats, \
    write 3 short, specific, actionable insights. Avoid medical claims. Respond with ONLY JSON:
    {"insights":[{"title":string (max 6 words),"detail":string (max 25 words),"tone":"positive"|"neutral"|"warning",\
    "symbol":SF Symbol name}]}
    """
}

enum AIJSON {
    /// Pulls the first top-level JSON object out of a model response (handles ```json fences and chatter).
    static func extractObject(_ text: String) -> Data? {
        var s = text
        if let thinkEnd = s.range(of: "</think>") { s = String(s[thinkEnd.upperBound...]) }
        guard let start = s.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        for i in s[start...].indices {
            let ch = s[i]
            if inString {
                if escaped { escaped = false }
                else if ch == "\\" { escaped = true }
                else if ch == "\"" { inString = false }
                continue
            }
            switch ch {
            case "\"": inString = true
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 { return String(s[start...i]).data(using: .utf8) }
            default: break
            }
        }
        return nil
    }

    static func decode<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
        guard let data = extractObject(text) else { throw AIError.badResponse("No JSON found.") }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw AIError.badResponse(error.localizedDescription) }
    }
}

extension UIImage {
    /// Downscales to keep uploads small and on-device vision fast.
    func jpegForAI(maxDimension: CGFloat = 1024, quality: CGFloat = 0.75) -> Data? {
        let longest = max(size.width, size.height)
        let scale = longest > maxDimension ? maxDimension / longest : 1
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}
