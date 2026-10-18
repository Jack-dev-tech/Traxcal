import Foundation
import Testing
@testable import Traxcal

@Suite("Nutrients")
struct NutrientsTests {
    @Test func scalingAndAddingKeepsOptionalsNil() {
        let a = Nutrients(calories: 100, protein: 10, carbs: 5, fat: 4, fiber: 2, sodium: 100)
        let b = Nutrients(calories: 50, protein: 2, carbs: 10, fat: 1)
        let sum = a.scaled(by: 2) + b
        #expect(sum.calories == 250)
        #expect(sum.protein == 22)
        #expect(sum.fiber == 4)
        #expect(sum.sodium == 200)
        #expect(sum.sugar == nil)
    }

    @Test func compactArrayDecoding() {
        let n = Nutrients(array: [590, 25, 46, 34, 3, 9, 11, 1050])
        #expect(n.calories == 590)
        #expect(n.saturatedFat == 11)
        #expect(n.sodium == 1050)
        #expect(n.caffeine == nil)
    }

    @Test func tdeeAndSuggestedGoalsAreSane() {
        var p = UserProfile()
        p.sex = .male; p.age = 30; p.heightCm = 180; p.weightKg = 80; p.activity = .moderate; p.objective = .lose
        let goals = p.suggestedGoals()
        let calories = try! #require(goals[.calories])
        #expect(calories > 1800 && calories < 2800)
        let macroCalories = goals[.protein]! * 4 + goals[.carbs]! * 4 + goals[.fat]! * 9
        #expect(abs(macroCalories - calories) < 20)
    }
}

@Suite("Bundled data")
struct DatasetTests {
    let provider = BundledFoodProvider.shared

    @Test func datasetsLoad() {
        #expect(provider.items.count > 300)
        #expect(provider.chipotle != nil)
    }

    @Test func everyItemHasPlausibleCalories() {
        // Alcohol (7 kcal/g) isn't a macro, so drinks like beer and wine are excluded.
        for item in provider.items where item.nutrients.calories > 60 && !["Beer", "Wine"].contains(where: { item.name.contains($0) }) {
            let macro = item.nutrients.macroCalories
            #expect(abs(macro - item.nutrients.calories) / item.nutrients.calories < 0.3, "\(item.displayName)")
        }
    }

    @Test(arguments: [
        ("big mac", "Big Mac"),
        ("shackburger", "ShackBurger (Single)"),
        ("mcdonalds nuggets", "Chicken McNuggets (10 pc)"),
        ("chipotle chicken bowl", "Chicken Burrito Bowl"),
        ("crunchwrap", "Crunchwrap Supreme"),
        ("double double", "Double-Double"),
    ])
    func universalSearchFindsAcrossRestaurants(query: String, expected: String) {
        let results = provider.search(query).prefix(5).map(\.name)
        #expect(results.contains(expected), "\(query) → \(results)")
    }

    @Test func fuzzyMatchingToleratesTypos() {
        #expect(provider.search("chik fil a sandwich").contains { $0.brand == "Chick-fil-A" })
        #expect(provider.search("starbuks latte").contains { $0.brand == "Starbucks" })
    }
}

@Suite("Chipotle builder")
struct ChipotleTests {
    let menu = BundledFoodProvider.shared.chipotle!

    @Test func burritoIncludesTortilla() {
        let burrito = menu.entrees.first { $0.id == "burrito" }!
        let bowl = menu.entrees.first { $0.id == "bowl" }!
        let picks: [String: ChipotleMenu.Portion] = ["chicken": .normal, "white-rice": .normal]
        let delta = menu.total(entree: burrito, selections: picks).calories - menu.total(entree: bowl, selections: picks).calories
        #expect(delta == 320)
    }

    @Test func portionsScale() {
        let bowl = menu.entrees.first { $0.id == "bowl" }!
        let normal = menu.total(entree: bowl, selections: ["chicken": .normal])
        let double = menu.total(entree: bowl, selections: ["chicken": .double])
        let light = menu.total(entree: bowl, selections: ["chicken": .light])
        #expect(double.protein == normal.protein * 2)
        #expect(light.calories == normal.calories / 2)
    }

    @Test func presetsAreSearchable() {
        let presets = menu.presetItems()
        #expect(presets.count == menu.presets.count)
        let chickenBowl = presets.first { $0.name == "Chicken Burrito Bowl" }!
        // rice 210 + beans 130 + chicken 180 + salsa 25 + cheese 110 + romaine 5
        #expect(chickenBowl.nutrients.calories == 660)
    }
}

@Suite("Search ranking")
struct RankingTests {
    @Test func liveResultsWinDuplicates() {
        let bundled = FoodItem(id: "b", name: "Big Mac", brand: "McDonald's", source: .restaurant,
                               servingDescription: "1", servingGrams: nil, nutrients: Nutrients(calories: 590))
        let live = FoodItem(id: "l", name: "Big Mac", brand: "McDonald's", source: .usda,
                            servingDescription: "1", servingGrams: nil, nutrients: Nutrients(calories: 563))
        let ranked = FoodSearchService.rank(query: "big mac", live: [live], bundled: [bundled])
        #expect(ranked.count == 1)
        #expect(ranked.first?.source == .usda)
    }

    @Test func irrelevantLiveResultsAreDropped() {
        let junk = FoodItem(id: "j", name: "Organic Kale Chips", brand: nil, source: .openFoodFacts,
                            servingDescription: "1", servingGrams: nil, nutrients: Nutrients(calories: 100))
        #expect(FoodSearchService.rank(query: "big mac", live: [junk], bundled: []).isEmpty)
    }

    @Test func usdaItemConvertsPer100gToServing() {
        let food = USDAFoodDataProvider.Food(
            fdcId: 1, description: "GREEK YOGURT", dataType: "Branded", brandOwner: "ACME", brandName: nil,
            servingSize: 170, servingSizeUnit: "g", householdServingFullText: "1 container",
            foodNutrients: [
                .init(nutrientNumber: "208", unitName: "KCAL", value: 59),
                .init(nutrientNumber: "203", unitName: "G", value: 10),
            ]
        )
        let item = try! #require(USDAFoodDataProvider.item(from: food))
        #expect(item.name == "Greek Yogurt")
        #expect(abs(item.nutrients.calories - 100.3) < 0.01)
        #expect(item.servingGrams == 170)
    }
}

@Suite("AI parsing")
struct AIParsingTests {
    @Test func extractsJSONFromChattyFencedResponse() throws {
        let text = """
        <think>let me think</think>
        Sure! Here you go:
        ```json
        {"mealName":"Breakfast","items":[{"name":"Egg","portion":"2 large","grams":"100","confidence":0.9,"calories":143,"protein":12.6,"carbs":0.7,"fat":9.5}],"notes":"Looks {tasty}"}
        ```
        """
        let analysis = try AIJSON.decode(FoodAnalysis.self, from: text)
        #expect(analysis.mealName == "Breakfast")
        #expect(analysis.items.count == 1)
        #expect(analysis.items[0].grams == 100)
        #expect(analysis.items[0].nutrients.protein == 12.6)
    }

    @Test func fillsMissingCaloriesFromMacros() throws {
        let json = #"{"items":[{"name":"Rice","protein":4,"carbs":45,"fat":0.5}]}"#
        let analysis = try AIJSON.decode(FoodAnalysis.self, from: json)
        #expect(analysis.items[0].nutrients.calories == 201)
        #expect(analysis.items[0].portion == "1 serving")
    }

    @Test func insightsDecodeWithDefaults() throws {
        struct Payload: Decodable { var insights: [Insight] }
        let json = #"{"insights":[{"title":"Nice","detail":"Good job"}]}"#
        let payload = try AIJSON.decode(Payload.self, from: json)
        #expect(payload.insights.first?.tone == .neutral)
        #expect(payload.insights.first?.symbol == "sparkles")
    }
}

@Suite("Trends")
struct TrendsTests {
    private func day(_ offset: Int, _ calories: Double, protein: Double = 100) -> DaySummary {
        DaySummary(date: Date.now.adding(days: -offset).startOfDay,
                   nutrients: Nutrients(calories: calories, protein: protein, carbs: 200, fat: 60),
                   entryCount: calories > 0 ? 3 : 0)
    }

    @Test func streakIgnoresUnloggedToday() {
        let report = TrendReport(days: [day(3, 0), day(2, 2000), day(1, 2100), day(0, 0)], goals: [.calories: 2000])
        #expect(report.streak == 2)
    }

    @Test func averagesOnlyLoggedDays() {
        let report = TrendReport(days: [day(2, 1800), day(1, 0), day(0, 2200)], goals: [:])
        #expect(report.average(.calories) == 2000)
        #expect(report.onTargetDays == 2)
    }

    @Test func ruleInsightsFlagProteinGap() {
        let report = TrendReport(days: [day(1, 2000, protein: 40), day(0, 2000, protein: 50)], goals: [.calories: 2000, .protein: 150])
        #expect(report.ruleBasedInsights().contains { $0.title == "Protein gap" })
    }

    @Test func deviceTierRecommendation() {
        let small = DeviceCapability(physicalMemoryGB: 3.7, modelIdentifier: "iPhone14,7")
        let pro = DeviceCapability(physicalMemoryGB: 7.5, modelIdentifier: "iPhone17,1")
        #expect(small.tier == .compact)
        #expect(pro.tier == .pro)
        #expect(LocalModelCatalog.recommended(for: small).runs(on: .compact))
        #expect(LocalModelCatalog.recommended(for: pro).vision)
    }
}
