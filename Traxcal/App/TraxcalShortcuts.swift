import AppIntents

struct TraxcalShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddWaterIntent(),
            phrases: ["Log water in \(.applicationName)", "Add a glass of water to \(.applicationName)"],
            shortTitle: "Log Water",
            systemImageName: "drop.fill"
        )
    }
}
