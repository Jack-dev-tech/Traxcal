import AppIntents
import WidgetKit

/// Interactive widget button and Shortcuts action: log a glass of water.
struct AddWaterIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Water"
    static var description = IntentDescription("Adds a glass of water to today's total in Traxcal.")

    @Parameter(title: "Milliliters", default: 250)
    var milliliters: Int

    init() {}

    init(milliliters: Int) {
        self.milliliters = milliliters
    }

    func perform() async throws -> some IntentResult {
        WaterStore.add(Double(milliliters))
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
