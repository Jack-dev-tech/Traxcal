import AppIntents
import Charts
import SwiftUI
import WidgetKit

@main
struct TraxcalWidgetBundle: WidgetBundle {
    var body: some Widget {
        CalorieWidget()
        WeekWidget()
    }
}

// MARK: - Timeline

struct SnapshotEntry: TimelineEntry {
    var date: Date
    var snapshot: WidgetSnapshot
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: context.isPreview ? .placeholder : current()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: .now, snapshot: current())
        // Refresh at midnight so the day resets even if the app isn't opened.
        let midnight = Calendar.current.startOfDay(for: .now.addingTimeInterval(86_400))
        completion(Timeline(entries: [entry], policy: .after(midnight)))
    }

    private func current() -> WidgetSnapshot {
        guard var snapshot = WidgetSnapshotStore.load() else {
            var empty = WidgetSnapshot.placeholder
            empty.calories = 0; empty.protein = 0; empty.carbs = 0; empty.fat = 0; empty.waterML = 0
            empty.lastFoodName = nil; empty.insight = "Open Traxcal to start tracking."
            empty.week = empty.week.map { WidgetSnapshot.Day(date: $0.date, calories: 0) }
            return empty
        }
        // A snapshot from a previous day means nothing has been logged today yet.
        if !Calendar.current.isDateInToday(snapshot.updatedAt) {
            snapshot.calories = 0; snapshot.protein = 0; snapshot.carbs = 0; snapshot.fat = 0
            snapshot.lastFoodName = nil
        }
        snapshot.waterML = WaterStore.amount()
        return snapshot
    }
}

// MARK: - Calorie widget (small, medium, lock screen)

struct CalorieWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SharedConfig.widgetKind, provider: SnapshotProvider()) { entry in
            CalorieWidgetView(snapshot: entry.snapshot)
                .containerBackground(for: .widget) { WidgetBackground() }
                .widgetURL(URL(string: "traxcal://today"))
        }
        .configurationDisplayName("Calories")
        .description("Calories left, macros and water at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct CalorieWidgetView: View {
    var snapshot: WidgetSnapshot
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: min(snapshot.progress, 1)) {
                Image(systemName: "flame.fill")
            } currentValueLabel: {
                Text("\(Int(snapshot.remaining))")
            }
            .gaugeStyle(.accessoryCircularCapacity)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label("\(Int(snapshot.remaining)) kcal left", systemImage: "flame.fill").font(.headline)
                Text("P \(Int(snapshot.protein)) · C \(Int(snapshot.carbs)) · F \(Int(snapshot.fat))").font(.caption)
                Gauge(value: min(snapshot.progress, 1)) { EmptyView() }.gaugeStyle(.accessoryLinearCapacity)
            }
        case .accessoryInline:
            Label("\(Int(snapshot.remaining)) kcal left", systemImage: "flame.fill")
        case .systemMedium:
            HStack(spacing: 16) {
                ring.frame(width: 118, height: 118)
                VStack(alignment: .leading, spacing: 8) {
                    macro("Protein", snapshot.protein, snapshot.proteinGoal, Palette.protein)
                    macro("Carbs", snapshot.carbs, snapshot.carbsGoal, Palette.carbs)
                    macro("Fat", snapshot.fat, snapshot.fatGoal, Palette.fat)
                    HStack {
                        Label("\(Int(snapshot.waterML)) ml", systemImage: "drop.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.water)
                        Spacer()
                        Button(intent: AddWaterIntent(milliliters: 250)) {
                            Label("250", systemImage: "plus").font(.caption.weight(.bold))
                        }
                        .buttonStyle(.bordered)
                        .tint(Palette.water)
                    }
                }
            }
        default:
            VStack(spacing: 6) {
                ring
                if let last = snapshot.lastFoodName {
                    Text(last).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }

    private var ring: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.1), lineWidth: 12)
            Circle()
                .trim(from: 0, to: min(snapshot.progress, 1))
                .stroke(Palette.calorieGradient, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(Int(snapshot.remaining))")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                Text("kcal left").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            }
        }
        .padding(4)
    }

    private func macro(_ title: String, _ value: Double, _ goal: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.caption2.weight(.semibold))
                Spacer()
                Text("\(Int(value))/\(Int(goal))g").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.1))
                    Capsule().fill(color).frame(width: geo.size.width * min(goal > 0 ? value / goal : 0, 1))
                }
            }
            .frame(height: 6)
        }
    }
}

// MARK: - Weekly widget (large)

struct WeekWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SharedConfig.weekWidgetKind, provider: SnapshotProvider()) { entry in
            WeekWidgetView(snapshot: entry.snapshot)
                .containerBackground(for: .widget) { WidgetBackground() }
                .widgetURL(URL(string: "traxcal://trends"))
        }
        .configurationDisplayName("Weekly Dashboard")
        .description("Today's totals, your week of calories and the latest AI insight.")
        .supportedFamilies([.systemLarge, .systemMedium])
    }
}

struct WeekWidgetView: View {
    var snapshot: WidgetSnapshot
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("TODAY").font(.caption2.weight(.heavy)).foregroundStyle(.secondary)
                    Text("\(Int(snapshot.calories)) / \(Int(snapshot.calorieGoal))")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                }
                Spacer()
                Text("P \(Int(snapshot.protein)) · C \(Int(snapshot.carbs)) · F \(Int(snapshot.fat))")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            Chart {
                ForEach(snapshot.week) { day in
                    BarMark(x: .value("Day", day.date, unit: .day), y: .value("kcal", day.calories))
                        .foregroundStyle(day.calories > snapshot.calorieGoal * 1.1 ? Palette.warning : Palette.calories)
                        .cornerRadius(5)
                }
                RuleMark(y: .value("Goal", snapshot.calorieGoal))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)) }
            }
            .chartYAxis(.hidden)

            if family == .systemLarge {
                if let insight = snapshot.insight {
                    Label(insight, systemImage: "sparkles")
                        .font(.caption)
                        .lineLimit(3)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.fat.opacity(0.15), in: .rect(cornerRadius: 12))
                }
                HStack {
                    Label("\(Int(snapshot.waterML)) / \(Int(snapshot.waterGoalML)) ml", systemImage: "drop.fill")
                        .font(.caption.weight(.semibold)).foregroundStyle(Palette.water)
                    Spacer()
                    Button(intent: AddWaterIntent(milliliters: 250)) {
                        Label("Water", systemImage: "plus").font(.caption.weight(.bold))
                    }
                    .buttonStyle(.bordered)
                    .tint(Palette.water)
                }
            }
        }
    }
}

struct WidgetBackground: View {
    var body: some View {
        LinearGradient(colors: [Palette.inkRaised, Palette.ink], startPoint: .top, endPoint: .bottom)
    }
}
