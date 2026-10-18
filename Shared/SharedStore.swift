import Foundation

/// Values shared between the app and the widget extension through the App Group.
enum SharedConfig {
    static let appGroupID = "group.com.traxcal.shared"
    static let widgetKind = "TraxcalCalorieWidget"
    static let weekWidgetKind = "TraxcalWeekWidget"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    static var containerURL: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }
}

/// A lightweight summary the app writes after every change so widgets can render without SwiftData.
struct WidgetSnapshot: Codable, Equatable {
    struct Day: Codable, Equatable, Identifiable {
        var date: Date
        var calories: Double
        var id: Date { date }
    }

    var updatedAt: Date
    var calories: Double
    var calorieGoal: Double
    var protein: Double
    var proteinGoal: Double
    var carbs: Double
    var carbsGoal: Double
    var fat: Double
    var fatGoal: Double
    var waterML: Double
    var waterGoalML: Double
    var lastFoodName: String?
    var insight: String?
    var week: [Day]

    var remaining: Double { max(calorieGoal - calories, 0) }
    var progress: Double { calorieGoal > 0 ? calories / calorieGoal : 0 }

    static let placeholder = WidgetSnapshot(
        updatedAt: .now, calories: 1420, calorieGoal: 2200,
        protein: 92, proteinGoal: 150, carbs: 160, carbsGoal: 240, fat: 48, fatGoal: 70,
        waterML: 1250, waterGoalML: 2500, lastFoodName: "Chicken Burrito Bowl",
        insight: "Protein is trending up 12% this week.",
        week: (0..<7).map { offset in
            Day(date: Calendar.current.date(byAdding: .day, value: offset - 6, to: .now)!,
                calories: [1850, 2100, 1990, 2300, 1700, 2050, 1420][offset])
        }
    )
}

enum WidgetSnapshotStore {
    private static let key = "widgetSnapshot.v1"

    static func load() -> WidgetSnapshot? {
        guard let data = SharedConfig.defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    static func save(_ snapshot: WidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        SharedConfig.defaults.set(data, forKey: key)
    }
}

/// Water is stored in the App Group so the interactive widget can add to it directly.
enum WaterStore {
    private static func key(for date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "water.\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    static func amount(on date: Date = .now) -> Double {
        SharedConfig.defaults.double(forKey: key(for: date))
    }

    static func add(_ milliliters: Double, on date: Date = .now) {
        let k = key(for: date)
        let next = max(SharedConfig.defaults.double(forKey: k) + milliliters, 0)
        SharedConfig.defaults.set(next, forKey: k)
        if var snapshot = WidgetSnapshotStore.load(), Calendar.current.isDateInToday(date) {
            snapshot.waterML = next
            WidgetSnapshotStore.save(snapshot)
        }
        // Remember additions (with when they happened) so the app can mirror them to Apple Health,
        // even when they came from the widget while the app was closed.
        var pending = SharedConfig.defaults.array(forKey: pendingKey) as? [[String: Double]] ?? []
        pending.append(["ml": milliliters, "at": Date.now.timeIntervalSince1970])
        SharedConfig.defaults.set(pending, forKey: pendingKey)
    }

    struct PendingWrite {
        var milliliters: Double
        var date: Date
    }

    private static let pendingKey = "water.pendingHealth.v2"

    /// Returns and clears water changes that have not been written to Apple Health yet, oldest first.
    static func drainPendingHealthWrites() -> [PendingWrite] {
        let pending = SharedConfig.defaults.array(forKey: pendingKey) as? [[String: Double]] ?? []
        SharedConfig.defaults.removeObject(forKey: pendingKey)
        return pending.compactMap { row in
            guard let ml = row["ml"], let at = row["at"] else { return nil }
            return PendingWrite(milliliters: ml, date: Date(timeIntervalSince1970: at))
        }
    }
}
