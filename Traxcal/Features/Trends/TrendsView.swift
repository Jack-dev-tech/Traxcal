import Charts
import SwiftUI

struct TrendsView: View {
    enum Range: Int, CaseIterable, Identifiable {
        case week = 7, month = 30, quarter = 90
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .week: "7D"
            case .month: "30D"
            case .quarter: "90D"
            }
        }
    }

    @Environment(FoodLogger.self) private var logger
    @Environment(GoalStore.self) private var goals
    @State private var range: Range = .week
    @State private var nutrient: NutrientKind = .protein
    @State private var selectedDate: Date?

    var body: some View {
        let _ = logger.changeCount
        let report = logger.report(days: range.rawValue)

        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("Range", selection: $range.animation(Theme.spring)) {
                        ForEach(Range.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .sensoryFeedback(.selection, trigger: range)

                    statTiles(report)
                    caloriesChart(report)
                    macroChart(report)
                    macroSplit(report)
                    nutrientChart(report)
                    InsightsSection()
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
            .navigationTitle("Trends")
        }
    }

    // MARK: Tiles

    private func statTiles(_ report: TrendReport) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            tile("Avg Calories", "\(Int(report.average(.calories)))", "kcal / day", "flame.fill", Palette.calories,
                 change: report.weekOverWeekChange(.calories))
            tile("Avg Protein", "\(Int(report.average(.protein)))", "g / day", "bolt.heart.fill", Palette.protein,
                 change: report.weekOverWeekChange(.protein))
            tile("Streak", "\(report.streak)", "days logged", "calendar", Palette.carbs, change: nil)
            tile("On Target", "\(report.onTargetDays)/\(report.complete.count)", "days within 10%", "target", Palette.fat, change: nil)
        }
    }

    private func tile(_ title: String, _ value: String, _ unit: String, _ symbol: String, _ color: Color, change: Double?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: symbol).foregroundStyle(color)
                Spacer()
                if let change {
                    Label("\(Int((abs(change) * 100).rounded()))%", systemImage: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
            Text(value).font(.display(28)).contentTransition(.numericText())
            Text("\(title) · \(unit)").font(.caption).foregroundStyle(.secondary)
        }
        .glassCard()
        .animation(Theme.spring, value: value)
    }

    // MARK: Charts

    private func caloriesChart(_ report: TrendReport) -> some View {
        let goal = goals.goal(.calories)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Calories").font(.headline)
            Chart {
                ForEach(report.days) { day in
                    if range == .week {
                        BarMark(x: .value("Day", day.date, unit: .day), y: .value("kcal", day.nutrients.calories))
                            .foregroundStyle(LinearGradient(colors: [Palette.calories, Palette.carbs], startPoint: .bottom, endPoint: .top))
                            .cornerRadius(6)
                    } else {
                        AreaMark(x: .value("Day", day.date, unit: .day), y: .value("kcal", day.nutrients.calories))
                            .foregroundStyle(LinearGradient(colors: [Palette.calories.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.catmullRom)
                        LineMark(x: .value("Day", day.date, unit: .day), y: .value("kcal", day.nutrients.calories))
                            .foregroundStyle(Palette.calories)
                            .interpolationMethod(.catmullRom)
                    }
                }
                RuleMark(y: .value("Goal", goal))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                if let selectedDate, let day = report.days.first(where: { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }) {
                    RuleMark(x: .value("Selected", day.date, unit: .day))
                        .foregroundStyle(.white.opacity(0.3))
                        .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                            VStack(spacing: 2) {
                                Text(day.date.formatted(.dateTime.month().day())).font(.caption2).foregroundStyle(.secondary)
                                Text("\(Int(day.nutrients.calories)) kcal").font(.caption.weight(.bold))
                            }
                            .padding(6)
                            .glassEffect(.regular, in: .rect(cornerRadius: 8))
                        }
                }
            }
            .chartXSelection(value: $selectedDate)
            .frame(height: 200)
            .sensoryFeedback(.selection, trigger: selectedDate)
        }
        .glassCard()
    }

    private struct MacroPoint: Identifiable {
        var date: Date
        var macro: String
        var grams: Double
        var id: String { "\(date.timeIntervalSince1970)-\(macro)" }
    }

    private func macroChart(_ report: TrendReport) -> some View {
        let points = report.days.flatMap { day in
            [
                MacroPoint(date: day.date, macro: "Protein", grams: day.nutrients.protein),
                MacroPoint(date: day.date, macro: "Carbs", grams: day.nutrients.carbs),
                MacroPoint(date: day.date, macro: "Fat", grams: day.nutrients.fat),
            ]
        }
        return VStack(alignment: .leading, spacing: 10) {
            Text("Macros").font(.headline)
            Chart(points) { point in
                BarMark(x: .value("Day", point.date, unit: .day), y: .value("Grams", point.grams))
                    .foregroundStyle(by: .value("Macro", point.macro))
                    .cornerRadius(3)
            }
            .chartForegroundStyleScale(["Protein": Palette.protein, "Carbs": Palette.carbs, "Fat": Palette.fat])
            .chartLegend(position: .top, alignment: .leading)
            .frame(height: 200)
        }
        .glassCard()
    }

    private func macroSplit(_ report: TrendReport) -> some View {
        let split = report.macroSplit
        let slices: [(String, Double, Color)] = [
            ("Protein", split.protein, Palette.protein), ("Carbs", split.carbs, Palette.carbs), ("Fat", split.fat, Palette.fat),
        ]
        return HStack(spacing: 20) {
            Chart(slices, id: \.0) { slice in
                SectorMark(angle: .value("Share", slice.1), innerRadius: .ratio(0.62), angularInset: 2)
                    .foregroundStyle(slice.2)
                    .cornerRadius(4)
            }
            .frame(width: 130, height: 130)
            VStack(alignment: .leading, spacing: 10) {
                Text("Calorie Split").font(.headline)
                ForEach(slices, id: \.0) { slice in
                    HStack {
                        Circle().fill(slice.2).frame(width: 8, height: 8)
                        Text(slice.0).font(.subheadline)
                        Spacer()
                        Text("\(Int((slice.1 * 100).rounded()))%").font(.subheadline.weight(.bold).monospacedDigit())
                    }
                }
            }
        }
        .glassCard()
    }

    private func nutrientChart(_ report: TrendReport) -> some View {
        let goal = goals.goal(nutrient)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Nutrient Trend").font(.headline)
                Spacer()
                Picker("Nutrient", selection: $nutrient.animation(Theme.spring)) {
                    ForEach(NutrientKind.allCases.filter { $0 != .calories }) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
            }
            Chart {
                ForEach(report.days) { day in
                    LineMark(x: .value("Day", day.date, unit: .day), y: .value(nutrient.title, day.nutrients.value(nutrient) ?? 0))
                        .foregroundStyle(Theme.color(for: nutrient))
                        .interpolationMethod(.catmullRom)
                        .symbol(.circle)
                }
                RuleMark(y: .value("Goal", goal))
                    .foregroundStyle(Theme.color(for: nutrient).opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("\(nutrient.isLimit ? "Limit" : "Goal") \(Int(goal)) \(nutrient.unit)").font(.caption2).foregroundStyle(.secondary)
                    }
            }
            .frame(height: 180)
            Text("Average \(report.average(nutrient).formatted(.number.precision(.fractionLength(0...1)))) \(nutrient.unit) per full day")
                .font(.caption).foregroundStyle(.secondary)
        }
        .glassCard()
    }
}
