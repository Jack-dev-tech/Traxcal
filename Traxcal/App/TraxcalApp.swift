import SwiftData
import SwiftUI

@main
struct TraxcalApp: App {
    let container: ModelContainer
    @State private var goals: GoalStore
    @State private var logger: FoodLogger
    @State private var insights = InsightService()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // The store lives in the App Group so it survives reinstalls of the widget and can be shared later.
        let url = SharedConfig.containerURL.appending(path: "Traxcal.store")
        let configuration = ModelConfiguration(url: url)
        do {
            container = try ModelContainer(for: FoodEntry.self, FavoriteFood.self, InsightRecord.self, configurations: configuration)
        } catch {
            // Fall back to an in-memory store rather than crash if the on-disk store is unreadable.
            container = try! ModelContainer(
                for: FoodEntry.self, FavoriteFood.self, InsightRecord.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        }
        let goals = GoalStore()
        _goals = State(initialValue: goals)
        _logger = State(initialValue: FoodLogger(context: container.mainContext, goals: goals))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(goals)
                .environment(logger)
                .environment(insights)
                .environment(AIRouter.shared)
                .environment(HealthKitService.shared)
                .environment(LocalModelManager.shared)
                .preferredColorScheme(.dark)
                .tint(Palette.calories)
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            logger.syncPendingWater()
            logger.refreshWidgets()
            Task { await HealthKitService.shared.refreshReadings() }
        }
    }
}
