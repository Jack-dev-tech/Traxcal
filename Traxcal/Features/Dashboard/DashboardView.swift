import Charts
import SwiftUI

struct DashboardView: View {
    var onLog: (LogAction) -> Void

    @Environment(GoalStore.self) private var goals
    @Environment(FoodLogger.self) private var logger
    @Environment(InsightService.self) private var insights
    @Environment(HealthKitService.self) private var health
    @State private var editing: FoodEntry?
    @State private var goalCelebrated = false

    var body: some View {
        // Reading changeCount subscribes this view to every log change.
        let _ = logger.changeCount
        let today = logger.entries(on: .now)
        let totals = today.map(\.total).sum()
        let report = logger.report(days: 7)

        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header(streak: logger.report(days: 30).streak)
                        .appearAnimation(index: 0)
                    CalorieHeroCard(eaten: totals.calories, goal: goals.goal(.calories), burned: health.activeEnergyToday)
                        .appearAnimation(index: 1)
                    macrosCard(totals).appearAnimation(index: 2)
                    WaterCard(goal: goals.waterGoalML).appearAnimation(index: 3)
                    microsCard(totals).appearAnimation(index: 4)
                    InsightsSection().appearAnimation(index: 5)
                    WeekChartCard(report: report, goal: goals.goal(.calories)).appearAnimation(index: 6)
                    mealsSection(today).appearAnimation(index: 7)
                    recentsSection.appearAnimation(index: 8)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .scrollIndicators(.hidden)
            .navigationBarHidden(true)
            .refreshable {
                await health.refreshReadings()
                await insights.load(logger: logger, force: true)
            }
            .sheet(item: $editing) { EditEntryView(entry: $0) }
            .task { await insights.load(logger: logger) }
            .sensoryFeedback(.success, trigger: goalCelebrated) { _, new in new }
            .onChange(of: totals.calories) { _, cal in
                let reached = cal >= goals.goal(.calories) * 0.95 && cal <= goals.goal(.calories) * 1.05
                if reached && !goalCelebrated { goalCelebrated = true }
            }
        }
    }

    private func header(streak: Int) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).month().day()).uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(greeting).font(.display(30))
            }
            Spacer()
            if streak > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill").symbolEffect(.pulse)
                    Text("\(streak)").font(.headline.monospacedDigit())
                }
                .foregroundStyle(Palette.calories)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .glassEffect(.regular.tint(Palette.calories.opacity(0.2)), in: .capsule)
            }
        }
        .padding(.top, 8)
    }

    private var greeting: String {
        let name = goals.profile.name.isEmpty ? "" : ", \(goals.profile.name)"
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: return "Good morning\(name)"
        case 12..<17: return "Good afternoon\(name)"
        default: return "Good evening\(name)"
        }
    }

    private func macrosCard(_ totals: Nutrients) -> some View {
        VStack(spacing: 14) {
            MacroBar(title: "Protein", value: totals.protein, goal: goals.goal(.protein), color: Palette.protein)
            MacroBar(title: "Carbs", value: totals.carbs, goal: goals.goal(.carbs), color: Palette.carbs)
            MacroBar(title: "Fat", value: totals.fat, goal: goals.goal(.fat), color: Palette.fat)
        }
        .glassCard()
    }

    private func microsCard(_ totals: Nutrients) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Nutrients").font(.headline)
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(NutrientKind.micros) { kind in
                        NutrientChip(kind: kind, value: totals.value(kind) ?? 0, goal: goals.goal(kind))
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .glassCard()
    }

    @ViewBuilder
    private func mealsSection(_ entries: [FoodEntry]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Today's Food", symbol: "fork.knife")
            if entries.isEmpty {
                Button { onLog(.search) } label: {
                    VStack(spacing: 10) {
                        Image(systemName: "plus.circle.dashed").font(.system(size: 36))
                        Text("Log your first meal").font(.headline)
                        Text("Search any restaurant or food, scan a photo, or build a Chipotle bowl.")
                            .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .glassCard()
                }
                .buttonStyle(.pressable)
            }
            ForEach(MealType.allCases) { meal in
                let items = entries.filter { $0.meal == meal }
                if !items.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label(meal.title, systemImage: meal.symbol).font(.subheadline.weight(.bold))
                            Spacer()
                            Text("\(Int(items.map(\.total.calories).reduce(0, +))) kcal")
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        ForEach(items) { entry in
                            EntryRow(entry: entry)
                                .contentShape(.rect)
                                .onTapGesture { editing = entry }
                                .contextMenu {
                                    Button("Edit", systemImage: "pencil") { editing = entry }
                                    Button("Log Again", systemImage: "arrow.clockwise") { logger.duplicate(entry); Haptics.success() }
                                    Button("Delete", systemImage: "trash", role: .destructive) { withAnimation { logger.delete(entry) } }
                                }
                        }
                    }
                    .glassCard()
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
        }
        .animation(Theme.spring, value: entries.count)
    }

    @ViewBuilder
    private var recentsSection: some View {
        let recents = logger.recentItems(limit: 10)
        if !recents.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(title: "Quick Add", symbol: "bolt.fill")
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(recents) { item in
                            Button {
                                logger.log(item, servings: 1, meal: .suggested())
                                Haptics.celebrate()
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.displayName).font(.subheadline.weight(.semibold)).lineLimit(2)
                                    Text("\(Int(item.nutrients.calories)) kcal").font(.caption).foregroundStyle(.secondary)
                                }
                                .frame(width: 140, height: 62, alignment: .topLeading)
                                .padding(12)
                                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
                            }
                            .buttonStyle(.pressable)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}

// MARK: - Cards

struct CalorieHeroCard: View {
    var eaten: Double
    var goal: Double
    var burned: Double

    var body: some View {
        let remaining = goal + burned - eaten
        HStack(spacing: 20) {
            ZStack {
                RingGauge(progress: goal > 0 ? eaten / (goal + burned) : 0, lineWidth: 20)
                VStack(spacing: 0) {
                    Text("\(Int(abs(remaining).rounded()))")
                        .font(.display(38))
                        .contentTransition(.numericText(value: remaining))
                        .animation(Theme.spring, value: remaining)
                    Text(remaining >= 0 ? "kcal left" : "kcal over")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(remaining >= 0 ? Color.secondary : Palette.warning)
                }
            }
            .frame(width: 160, height: 160)

            VStack(alignment: .leading, spacing: 14) {
                stat("Eaten", eaten, "fork.knife", Palette.calories)
                stat("Goal", goal, "target", .white)
                stat("Burned", burned, "flame", Palette.protein)
            }
        }
        .frame(maxWidth: .infinity)
        .glassCard(padding: 20, tint: Palette.calories)
    }

    private func stat(_ title: String, _ value: Double, _ symbol: String, _ color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(color).frame(width: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text("\(Int(value.rounded()))")
                    .font(.title3.weight(.bold).monospacedDigit())
                    .contentTransition(.numericText(value: value))
            }
        }
    }
}

struct NutrientChip: View {
    var kind: NutrientKind
    var value: Double
    var goal: Double

    var body: some View {
        let progress = goal > 0 ? value / goal : 0
        let over = kind.isLimit && progress > 1
        VStack(alignment: .leading, spacing: 6) {
            Text(kind.title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value < 10 ? value.formatted(.number.precision(.fractionLength(0...1))) : "\(Int(value.rounded()))")
                    .font(.headline.monospacedDigit())
                Text(kind.unit).font(.caption2).foregroundStyle(.secondary)
            }
            Gauge(value: min(progress, 1)) { EmptyView() }
                .gaugeStyle(.accessoryLinearCapacity)
                .tint(over ? Palette.warning : Theme.color(for: kind))
        }
        .frame(width: 104)
        .padding(12)
        .background(.white.opacity(0.05), in: .rect(cornerRadius: 16))
    }
}

struct WaterCard: View {
    var goal: Double
    @Environment(FoodLogger.self) private var logger
    @State private var wave = false

    var body: some View {
        let _ = logger.changeCount
        let amount = WaterStore.amount()
        HStack(spacing: 16) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 14).fill(Palette.water.opacity(0.12))
                RoundedRectangle(cornerRadius: 14)
                    .fill(LinearGradient(colors: [Palette.water, Palette.water.opacity(0.6)], startPoint: .top, endPoint: .bottom))
                    .frame(height: 70 * min(amount / max(goal, 1), 1))
                    .animation(Theme.spring, value: amount)
                Image(systemName: "drop.fill")
                    .foregroundStyle(.white)
                    .padding(.bottom, 8)
                    .symbolEffect(.bounce, value: amount)
            }
            .frame(width: 44, height: 70)

            VStack(alignment: .leading, spacing: 2) {
                Text("Water").font(.headline)
                Text("\(Int(amount)) / \(Int(goal)) ml")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText(value: amount))
            }
            Spacer()
            Button {
                logger.addWater(-250)
            } label: {
                Image(systemName: "minus").frame(width: 38, height: 38).glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.pressable)
            .disabled(amount <= 0)
            Button {
                logger.addWater(250)
                Haptics.tap()
            } label: {
                Label("250", systemImage: "plus")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Palette.water, in: .capsule)
            }
            .buttonStyle(.pressable)
        }
        .glassCard()
    }
}

struct EntryRow: View {
    var entry: FoodEntry

    var body: some View {
        HStack(spacing: 12) {
            if let data = entry.photo, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill().frame(width: 42, height: 42).clipShape(.rect(cornerRadius: 10))
            } else {
                Image(systemName: entry.source.symbol)
                    .foregroundStyle(Palette.calories)
                    .frame(width: 42, height: 42)
                    .background(.white.opacity(0.06), in: .rect(cornerRadius: 10))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.displayName).font(.subheadline.weight(.semibold)).lineLimit(1)
                HStack(spacing: 6) {
                    Text(entry.servings == 1 ? entry.servingDescription : "\(entry.servings.formatted(.number.precision(.fractionLength(0...2))))× \(entry.servingDescription)")
                        .lineLimit(1)
                    Text("·")
                    Text(entry.date.formatted(date: .omitted, time: .shortened))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                MacroLine(nutrients: entry.total)
            }
            Spacer()
            Text("\(Int(entry.total.calories.rounded()))")
                .font(.headline.monospacedDigit())
            + Text(" kcal").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct WeekChartCard: View {
    var report: TrendReport
    var goal: Double
    @State private var selected: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("This Week").font(.headline)
                Spacer()
                Text("avg \(Int(report.average(.calories))) kcal").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            Chart {
                ForEach(report.days) { day in
                    BarMark(
                        x: .value("Day", day.date, unit: .day),
                        y: .value("Calories", day.nutrients.calories)
                    )
                    .foregroundStyle(
                        day.nutrients.calories > goal * 1.1
                            ? AnyShapeStyle(Palette.warning.gradient)
                            : AnyShapeStyle(LinearGradient(colors: [Palette.calories, Palette.carbs], startPoint: .bottom, endPoint: .top))
                    )
                    .cornerRadius(8)
                    .opacity(selected == nil || Calendar.current.isDate(selected!, inSameDayAs: day.date) ? 1 : 0.4)
                }
                RuleMark(y: .value("Goal", goal))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("Goal").font(.caption2).foregroundStyle(.secondary)
                    }
                if let selected, let day = report.days.first(where: { Calendar.current.isDate($0.date, inSameDayAs: selected) }) {
                    RuleMark(x: .value("Selected", day.date, unit: .day))
                        .foregroundStyle(.clear)
                        .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                            VStack(spacing: 2) {
                                Text("\(Int(day.nutrients.calories)) kcal").font(.caption.weight(.bold))
                                MacroLine(nutrients: day.nutrients)
                            }
                            .padding(8)
                            .glassEffect(.regular, in: .rect(cornerRadius: 10))
                        }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                }
            }
            .chartYAxis(.hidden)
            .chartXSelection(value: $selected)
            .frame(height: 170)
            .sensoryFeedback(.selection, trigger: selected)
        }
        .glassCard()
    }
}

struct InsightsSection: View {
    @Environment(InsightService.self) private var insights
    @Environment(FoodLogger.self) private var logger

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "sparkles").foregroundStyle(Palette.fat).symbolEffect(.variableColor.iterative, isActive: insights.isLoading)
                Text("AI Trends").font(.title3.weight(.bold))
                Spacer()
                Text(insights.source).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Button {
                    Haptics.tap()
                    Task { await insights.load(logger: logger, force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise").font(.subheadline.weight(.bold))
                }
                .disabled(insights.isLoading)
            }
            .padding(.horizontal, 4)

            if insights.isLoading {
                ForEach(0..<2, id: \.self) { _ in ShimmerView().frame(height: 64) }
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(insights.insights) { insight in
                            InsightCard(insight: insight)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollIndicators(.hidden)
            }
        }
    }
}

struct InsightCard: View {
    var insight: Insight

    private var color: Color {
        switch insight.tone {
        case .positive: Palette.protein
        case .neutral: Palette.water
        case .warning: Palette.carbs
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: UIImage(systemName: insight.symbol) == nil ? "sparkles" : insight.symbol)
                .font(.title3)
                .foregroundStyle(color)
            Text(insight.title).font(.headline).lineLimit(2)
            Text(insight.detail).font(.caption).foregroundStyle(.secondary).lineLimit(4)
            Spacer(minLength: 0)
        }
        .frame(width: 220, height: 140, alignment: .topLeading)
        .padding(14)
        .glassEffect(.regular.tint(color.opacity(0.15)), in: .rect(cornerRadius: 22))
    }
}
