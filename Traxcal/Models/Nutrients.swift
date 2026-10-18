import Foundation

/// Nutrient amounts for one serving (or a total). Macros in grams, minerals in milligrams,
/// vitamin D in micrograms. Optional micronutrients are `nil` when the source doesn't report them.
struct Nutrients: Codable, Hashable, Sendable {
    var calories: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    var fiber: Double? = nil
    var sugar: Double? = nil
    var saturatedFat: Double? = nil
    var cholesterol: Double? = nil   // mg
    var sodium: Double? = nil        // mg
    var potassium: Double? = nil     // mg
    var calcium: Double? = nil       // mg
    var iron: Double? = nil          // mg
    var vitaminC: Double? = nil      // mg
    var vitaminD: Double? = nil      // mcg
    var caffeine: Double? = nil      // mg

    static let zero = Nutrients()

    /// Calories implied by the macros (4/4/9). Used to sanity-check AI estimates.
    var macroCalories: Double { protein * 4 + carbs * 4 + fat * 9 }

    func scaled(by factor: Double) -> Nutrients {
        func s(_ v: Double?) -> Double? { v.map { $0 * factor } }
        return Nutrients(
            calories: calories * factor, protein: protein * factor, carbs: carbs * factor,
            fat: fat * factor, fiber: s(fiber), sugar: s(sugar), saturatedFat: s(saturatedFat),
            cholesterol: s(cholesterol), sodium: s(sodium), potassium: s(potassium),
            calcium: s(calcium), iron: s(iron), vitaminC: s(vitaminC), vitaminD: s(vitaminD),
            caffeine: s(caffeine)
        )
    }

    static func + (lhs: Nutrients, rhs: Nutrients) -> Nutrients {
        func add(_ a: Double?, _ b: Double?) -> Double? {
            switch (a, b) {
            case (nil, nil): return nil
            default: return (a ?? 0) + (b ?? 0)
            }
        }
        return Nutrients(
            calories: lhs.calories + rhs.calories, protein: lhs.protein + rhs.protein,
            carbs: lhs.carbs + rhs.carbs, fat: lhs.fat + rhs.fat,
            fiber: add(lhs.fiber, rhs.fiber), sugar: add(lhs.sugar, rhs.sugar),
            saturatedFat: add(lhs.saturatedFat, rhs.saturatedFat),
            cholesterol: add(lhs.cholesterol, rhs.cholesterol), sodium: add(lhs.sodium, rhs.sodium),
            potassium: add(lhs.potassium, rhs.potassium), calcium: add(lhs.calcium, rhs.calcium),
            iron: add(lhs.iron, rhs.iron), vitaminC: add(lhs.vitaminC, rhs.vitaminC),
            vitaminD: add(lhs.vitaminD, rhs.vitaminD), caffeine: add(lhs.caffeine, rhs.caffeine)
        )
    }

    static func += (lhs: inout Nutrients, rhs: Nutrients) { lhs = lhs + rhs }
}

extension Sequence where Element == Nutrients {
    func sum() -> Nutrients { reduce(.zero, +) }
}

/// Describes every tracked nutrient so UI lists, goals and charts can be data-driven.
enum NutrientKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case calories, protein, carbs, fat, fiber, sugar, saturatedFat, cholesterol, sodium
    case potassium, calcium, iron, vitaminC, vitaminD, caffeine

    var id: String { rawValue }

    var title: String {
        switch self {
        case .calories: "Calories"
        case .protein: "Protein"
        case .carbs: "Carbs"
        case .fat: "Fat"
        case .fiber: "Fiber"
        case .sugar: "Sugar"
        case .saturatedFat: "Saturated Fat"
        case .cholesterol: "Cholesterol"
        case .sodium: "Sodium"
        case .potassium: "Potassium"
        case .calcium: "Calcium"
        case .iron: "Iron"
        case .vitaminC: "Vitamin C"
        case .vitaminD: "Vitamin D"
        case .caffeine: "Caffeine"
        }
    }

    var unit: String {
        switch self {
        case .calories: "kcal"
        case .protein, .carbs, .fat, .fiber, .sugar, .saturatedFat: "g"
        case .vitaminD: "mcg"
        default: "mg"
        }
    }

    /// Default daily reference values (FDA Daily Values where they exist).
    var defaultGoal: Double {
        switch self {
        case .calories: 2000
        case .protein: 120
        case .carbs: 225
        case .fat: 70
        case .fiber: 28
        case .sugar: 50
        case .saturatedFat: 20
        case .cholesterol: 300
        case .sodium: 2300
        case .potassium: 4700
        case .calcium: 1300
        case .iron: 18
        case .vitaminC: 90
        case .vitaminD: 20
        case .caffeine: 400
        }
    }

    /// Whether going over the goal is the "bad" direction (a limit rather than a target).
    var isLimit: Bool {
        switch self {
        case .sugar, .saturatedFat, .cholesterol, .sodium, .caffeine: true
        default: false
        }
    }

    var keyPath: WritableKeyPath<Nutrients, Double?>? {
        switch self {
        case .calories, .protein, .carbs, .fat: nil
        case .fiber: \.fiber
        case .sugar: \.sugar
        case .saturatedFat: \.saturatedFat
        case .cholesterol: \.cholesterol
        case .sodium: \.sodium
        case .potassium: \.potassium
        case .calcium: \.calcium
        case .iron: \.iron
        case .vitaminC: \.vitaminC
        case .vitaminD: \.vitaminD
        case .caffeine: \.caffeine
        }
    }

    static let micros: [NutrientKind] = [
        .fiber, .sugar, .saturatedFat, .sodium, .cholesterol, .potassium, .calcium, .iron,
        .vitaminC, .vitaminD, .caffeine,
    ]
}

extension Nutrients {
    func value(_ kind: NutrientKind) -> Double? {
        switch kind {
        case .calories: calories
        case .protein: protein
        case .carbs: carbs
        case .fat: fat
        default: self[keyPath: kind.keyPath!]
        }
    }

    mutating func set(_ kind: NutrientKind, _ value: Double?) {
        switch kind {
        case .calories: calories = value ?? 0
        case .protein: protein = value ?? 0
        case .carbs: carbs = value ?? 0
        case .fat: fat = value ?? 0
        default: self[keyPath: kind.keyPath!] = value
        }
    }
}
