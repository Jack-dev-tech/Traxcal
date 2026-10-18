import SwiftUI

/// Serving picker + nutrient preview + log button for any food item.
struct FoodDetailView: View {
    var item: FoodItem
    var onLogged: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(FoodLogger.self) private var logger
    @State private var option: ServingOption
    @State private var servings: Double = 1
    @State private var meal: MealType = .suggested()
    @State private var date: Date = .now
    @State private var isFavorite = false
    @State private var logged = false

    init(item: FoodItem, onLogged: @escaping () -> Void) {
        self.item = item
        self.onLogged = onLogged
        _option = State(initialValue: item.allServingOptions[0])
    }

    private var nutrients: Nutrients { item.nutrients.scaled(by: option.multiplier * servings) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 6) {
                        SourceBadge(source: item.source)
                        Text(item.name).font(.display(26, weight: .bold)).multilineTextAlignment(.center)
                        if let brand = item.brand { Text(brand).font(.headline).foregroundStyle(Palette.calories) }
                    }
                    .padding(.top, 8)

                    MacroDonut(nutrients: nutrients)
                        .frame(height: 190)

                    VStack(spacing: 14) {
                        if item.allServingOptions.count > 1 {
                            Picker("Serving", selection: $option) {
                                ForEach(item.allServingOptions) { Text($0.label).tag($0) }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Text(option.label).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        HStack {
                            Text("Servings").font(.headline)
                            Spacer()
                            ServingStepper(value: $servings, step: 0.25)
                        }
                        Picker("Meal", selection: $meal) {
                            ForEach(MealType.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .sensoryFeedback(.selection, trigger: meal)
                        DatePicker("Time", selection: $date)
                    }
                    .glassCard()

                    NutritionFactsList(nutrients: nutrients).glassCard()
                }
                .padding(16)
            }
            .safeAreaInset(edge: .bottom) {
                PrimaryButton(title: logged ? "Logged!" : "Log \(Int(nutrients.calories.rounded())) kcal", symbol: logged ? "checkmark" : "plus") {
                    log()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .disabled(logged)
            }
            .background(AuroraBackground().opacity(0.5))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close", systemImage: "xmark") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        logger.toggleFavorite(item)
                        isFavorite.toggle()
                    } label: {
                        Image(systemName: isFavorite ? "star.fill" : "star")
                            .foregroundStyle(isFavorite ? Palette.carbs : .primary)
                            .symbolEffect(.bounce, value: isFavorite)
                    }
                    .sensoryFeedback(.impact(weight: .light), trigger: isFavorite)
                }
            }
            .onAppear { isFavorite = logger.isFavorite(item) }
        }
        .presentationDetents([.large])
        .presentationBackground(.ultraThinMaterial)
    }

    private func log() {
        var logItem = item
        logItem.nutrients = item.nutrients.scaled(by: option.multiplier)
        logItem.servingDescription = option.label
        logItem.servingGrams = option.grams
        logger.log(logItem, servings: servings, meal: meal, date: date)
        Haptics.celebrate()
        withAnimation(Theme.bouncy) { logged = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            dismiss()
            onLogged()
        }
    }
}

/// Donut of calories split by macro, with the calorie count in the middle.
struct MacroDonut: View {
    var nutrients: Nutrients

    var body: some View {
        let p = nutrients.protein * 4, c = nutrients.carbs * 4, f = nutrients.fat * 9
        let total = max(p + c + f, 1)
        HStack(spacing: 24) {
            ZStack {
                Circle().stroke(.white.opacity(0.08), lineWidth: 18)
                arc(from: 0, to: p / total, color: Palette.protein)
                arc(from: p / total, to: (p + c) / total, color: Palette.carbs)
                arc(from: (p + c) / total, to: 1, color: Palette.fat)
                VStack(spacing: 0) {
                    Text("\(Int(nutrients.calories.rounded()))")
                        .font(.display(34))
                        .contentTransition(.numericText(value: nutrients.calories))
                    Text("kcal").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(width: 150, height: 150)
            .animation(Theme.spring, value: nutrients)

            VStack(alignment: .leading, spacing: 12) {
                legend("Protein", nutrients.protein, p / total, Palette.protein)
                legend("Carbs", nutrients.carbs, c / total, Palette.carbs)
                legend("Fat", nutrients.fat, f / total, Palette.fat)
            }
        }
    }

    private func arc(from: Double, to: Double, color: Color) -> some View {
        Circle()
            .trim(from: from, to: max(from, to - 0.004))
            .stroke(color, style: StrokeStyle(lineWidth: 18, lineCap: .butt))
            .rotationEffect(.degrees(-90))
    }

    private func legend(_ title: String, _ grams: Double, _ share: Double, _ color: Color) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(grams.formatted(.number.precision(.fractionLength(0...1))))g")
                    .font(.headline.monospacedDigit())
                    .contentTransition(.numericText(value: grams))
                Text("\(title) · \(Int((share * 100).rounded()))%").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// Label-style list of every nutrient that has a value.
struct NutritionFactsList: View {
    var nutrients: Nutrients

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Nutrition Facts").font(.headline)
            ForEach(NutrientKind.allCases) { kind in
                if let value = nutrients.value(kind) {
                    HStack {
                        Circle().fill(Theme.color(for: kind)).frame(width: 6, height: 6)
                        Text(kind.title).font(.subheadline)
                        Spacer()
                        Text("\(value.formatted(.number.precision(.fractionLength(0...1)))) \(kind.unit)")
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .contentTransition(.numericText(value: value))
                    }
                    if kind != NutrientKind.allCases.last { Divider().opacity(0.3) }
                }
            }
        }
        .animation(Theme.spring, value: nutrients)
    }
}
