import Foundation
import Observation

/// The user's body profile and daily targets. Persisted as JSON in the App Group defaults.
struct UserProfile: Codable, Equatable {
    enum Sex: String, Codable, CaseIterable, Identifiable { case female, male, other; var id: String { rawValue } }
    enum Activity: String, Codable, CaseIterable, Identifiable {
        case sedentary, light, moderate, active, athlete
        var id: String { rawValue }
        var multiplier: Double {
            switch self {
            case .sedentary: 1.2
            case .light: 1.375
            case .moderate: 1.55
            case .active: 1.725
            case .athlete: 1.9
            }
        }
        var title: String {
            switch self {
            case .sedentary: "Sedentary"
            case .light: "Lightly active"
            case .moderate: "Moderately active"
            case .active: "Very active"
            case .athlete: "Athlete"
            }
        }
    }
    enum Objective: String, Codable, CaseIterable, Identifiable {
        case lose, maintain, gain
        var id: String { rawValue }
        var title: String {
            switch self {
            case .lose: "Lose weight"
            case .maintain: "Maintain"
            case .gain: "Build muscle"
            }
        }
        var calorieDelta: Double {
            switch self {
            case .lose: -500
            case .maintain: 0
            case .gain: 300
            }
        }
    }

    var name: String = ""
    var sex: Sex = .other
    var age: Int = 30
    var heightCm: Double = 172
    var weightKg: Double = 75
    var activity: Activity = .moderate
    var objective: Objective = .maintain
    var useMetric: Bool = Locale.current.measurementSystem == .metric

    /// Mifflin–St Jeor basal metabolic rate.
    var bmr: Double {
        let base = 10 * weightKg + 6.25 * heightCm - 5 * Double(age)
        switch sex {
        case .male: return base + 5
        case .female: return base - 161
        case .other: return base - 78
        }
    }

    var tdee: Double { bmr * activity.multiplier }

    /// Active energy beyond what the activity level already counts in TDEE.
    /// The 1.2 sedentary factor covers daily life; everything above it is exercise the goal already includes.
    func extraBurn(activeEnergy: Double) -> Double {
        max(0, activeEnergy - (tdee - bmr * 1.2))
    }

    /// Suggested goals for this profile: protein ~1.8 g/kg (2.2 when gaining), fat 28% of calories.
    func suggestedGoals() -> [NutrientKind: Double] {
        let calories = max((tdee + objective.calorieDelta).rounded(), 1200)
        let protein = (weightKg * (objective == .gain ? 2.0 : 1.8)).rounded()
        let fat = (calories * 0.28 / 9).rounded()
        let carbs = max(((calories - protein * 4 - fat * 9) / 4).rounded(), 50)
        var goals = Dictionary(uniqueKeysWithValues: NutrientKind.allCases.map { ($0, $0.defaultGoal) })
        goals[.calories] = calories
        goals[.protein] = protein
        goals[.fat] = fat
        goals[.carbs] = carbs
        goals[.fiber] = (calories / 1000 * 14).rounded()
        return goals
    }
}

@Observable
final class GoalStore {
    private static let profileKey = "profile.v1"
    private static let goalsKey = "goals.v1"
    private static let waterKey = "waterGoal.v1"
    private static let onboardedKey = "onboarded.v1"

    var profile: UserProfile { didSet { persist() } }
    var goals: [NutrientKind: Double] { didSet { persist() } }
    var waterGoalML: Double { didSet { persist() } }
    var hasOnboarded: Bool { didSet { persist() } }

    init(defaults: UserDefaults = SharedConfig.defaults) {
        self.defaults = defaults
        let decoder = JSONDecoder()
        let profile = defaults.data(forKey: Self.profileKey).flatMap { try? decoder.decode(UserProfile.self, from: $0) } ?? UserProfile()
        self.profile = profile
        let stored = defaults.data(forKey: Self.goalsKey).flatMap { try? decoder.decode([String: Double].self, from: $0) }
        if let stored {
            var g: [NutrientKind: Double] = [:]
            for kind in NutrientKind.allCases { g[kind] = stored[kind.rawValue] ?? kind.defaultGoal }
            self.goals = g
        } else {
            self.goals = profile.suggestedGoals()
        }
        let water = defaults.double(forKey: Self.waterKey)
        self.waterGoalML = water > 0 ? water : 2500
        self.hasOnboarded = defaults.bool(forKey: Self.onboardedKey)
    }

    private let defaults: UserDefaults

    func goal(_ kind: NutrientKind) -> Double { goals[kind] ?? kind.defaultGoal }

    func applySuggestedGoals() { goals = profile.suggestedGoals() }

    private func persist() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(profile) { defaults.set(data, forKey: Self.profileKey) }
        let raw = Dictionary(uniqueKeysWithValues: goals.map { ($0.key.rawValue, $0.value) })
        if let data = try? encoder.encode(raw) { defaults.set(data, forKey: Self.goalsKey) }
        defaults.set(waterGoalML, forKey: Self.waterKey)
        defaults.set(hasOnboarded, forKey: Self.onboardedKey)
    }
}
