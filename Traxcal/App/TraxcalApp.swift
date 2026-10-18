import SwiftData
import SwiftUI

@main
struct TraxcalApp: App {
    let container: ModelContainer
    @State private var goals: GoalStore
    @State private var logger: FoodLogger
    @State private var insights = InsightService()
    /// Set when the saved database couldn't be opened and the app is running on a temporary store.
    @State private var storeError: String?
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // The store lives in the App Group so it survives reinstalls of the widget and can be shared later.
        let url = SharedConfig.containerURL.appending(path: "Traxcal.store")
        let configuration = ModelConfiguration(url: url)
        var storeError: String?
        do {
            container = try ModelContainer(for: FoodEntry.self, FavoriteFood.self, InsightRecord.self, configurations: configuration)
        } catch {
            // Fall back to an in-memory store rather than crash, but tell the user nothing will be kept.
            storeError = error.localizedDescription
            container = try! ModelContainer(
                for: FoodEntry.self, FavoriteFood.self, InsightRecord.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        }
        _storeError = State(initialValue: storeError)
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
                .alert("Your food log couldn't be loaded", isPresented: Binding(
                    get: { storeError != nil }, set: { if !$0 { storeError = nil } }
                )) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("Traxcal is running on a temporary store, and anything you log now will be lost when the app closes. Try restarting the app. (\(storeError ?? ""))")
                }
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            logger.syncPendingWater()
            logger.syncUnsyncedToHealth()
            logger.refreshWidgets()
            Task { await HealthKitService.shared.refreshReadings() }
        }
    }
}
