import SwiftUI

/// Review AI-detected foods: adjust portions, edit numbers, remove items, then log.
struct AnalysisReviewView: View {
    var photo: UIImage?
    var onDone: () -> Void

    @Environment(FoodLogger.self) private var logger
    @State private var items: [FoodAnalysis.Item]
    @State private var scales: [UUID: Double] = [:]
    @State private var meal: MealType = .suggested()
    @State private var combine = false
    @State private var editingItem: FoodAnalysis.Item?
    private let mealName: String?
    private let notes: String?

    init(analysis: FoodAnalysis, photo: UIImage?, onDone: @escaping () -> Void) {
        self.photo = photo
        self.onDone = onDone
        self.mealName = analysis.mealName
        self.notes = analysis.notes
        _items = State(initialValue: analysis.items)
    }

    private func scaled(_ item: FoodAnalysis.Item) -> Nutrients { item.nutrients.scaled(by: scales[item.id] ?? 1) }
    private var total: Nutrients { items.map(scaled).sum() }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let photo {
                    Image(uiImage: photo).resizable().scaledToFill()
                        .frame(height: 180).frame(maxWidth: .infinity)
                        .clipShape(.rect(cornerRadius: Theme.corner))
                }
                VStack(spacing: 6) {
                    Text(mealName ?? "Your meal").font(.display(24, weight: .bold))
                    MacroDonut(nutrients: total).frame(height: 170)
                }
                .glassCard()

                ForEach(items) { item in
                    itemCard(item)
                        .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .move(edge: .trailing).combined(with: .opacity)))
                }

                if let notes, !notes.isEmpty {
                    Label(notes, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                }

                VStack(spacing: 12) {
                    Picker("Meal", selection: $meal) {
                        ForEach(MealType.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Toggle("Log as one combined entry", isOn: $combine)
                }
                .glassCard()

                Text("AI estimates can be off by 20% or more. Adjust portions for best accuracy.")
                    .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(16)
            .animation(Theme.spring, value: items)
        }
        .navigationTitle("Review")
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: "Log \(Int(total.calories.rounded())) kcal", symbol: "checkmark", color: Palette.fat) { logAll() }
                .disabled(items.isEmpty)
                .padding()
        }
        .sheet(item: $editingItem) { item in
            EditAnalysisItemView(item: item) { updated in
                if let i = items.firstIndex(where: { $0.id == updated.id }) { items[i] = updated }
            }
        }
    }

    private func itemCard(_ item: FoodAnalysis.Item) -> some View {
        let n = scaled(item)
        let scale = scales[item.id] ?? 1
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name).font(.headline)
                    Text(scale == 1 ? item.portion : "\(scale.formatted(.number.precision(.fractionLength(0...2))))× \(item.portion)")
                        .font(.caption).foregroundStyle(.secondary)
                    ConfidencePill(confidence: item.confidence)
                }
                Spacer()
                Text("\(Int(n.calories.rounded())) kcal")
                    .font(.headline.monospacedDigit())
                    .contentTransition(.numericText(value: n.calories))
            }
            MacroLine(nutrients: n)
            HStack {
                Text("Portion").font(.caption).foregroundStyle(.secondary)
                Slider(value: Binding(get: { scales[item.id] ?? 1 }, set: { scales[item.id] = ($0 * 4).rounded() / 4 }), in: 0.25...3, step: 0.25)
                    .tint(Palette.fat)
                    .sensoryFeedback(.selection, trigger: scales[item.id])
            }
            HStack {
                Button("Edit", systemImage: "pencil") { editingItem = item }
                Spacer()
                Button("Remove", systemImage: "trash", role: .destructive) {
                    withAnimation { items.removeAll { $0.id == item.id } }
                    Haptics.warning()
                }
            }
            .font(.caption.weight(.semibold))
        }
        .glassCard()
    }

    private func logAll() {
        let photoData = photo?.jpegForAI(maxDimension: 600, quality: 0.6)
        if combine {
            let item = FoodItem(
                id: "ai-meal-\(UUID().uuidString)", name: mealName ?? items.map(\.name).joined(separator: ", "),
                brand: nil, source: .ai, servingDescription: "1 meal", servingGrams: nil, nutrients: total
            )
            logger.log(item, servings: 1, meal: meal, photo: photoData)
        } else {
            for (index, item) in items.enumerated() {
                var food = item.asFoodItem
                food.nutrients = scaled(item)
                let scale = scales[item.id] ?? 1
                if scale != 1 { food.servingDescription = "\(scale.formatted())× \(item.portion)" }
                logger.log(food, servings: 1, meal: meal, photo: index == 0 ? photoData : nil)
            }
        }
        Haptics.celebrate()
        onDone()
    }
}

struct ConfidencePill: View {
    var confidence: Double

    private var label: String {
        confidence >= 0.75 ? "High confidence" : confidence >= 0.5 ? "Medium confidence" : "Low confidence"
    }

    private var color: Color {
        confidence >= 0.75 ? Palette.protein : confidence >= 0.5 ? Palette.carbs : Palette.warning
    }

    var body: some View {
        Text(label)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.18), in: .capsule)
            .foregroundStyle(color)
    }
}

private struct EditAnalysisItemView: View {
    @State var item: FoodAnalysis.Item
    var onSave: (FoodAnalysis.Item) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Food") {
                    TextField("Name", text: $item.name)
                    TextField("Portion", text: $item.portion)
                }
                Section("Nutrition") {
                    ForEach([NutrientKind.calories, .protein, .carbs, .fat, .fiber, .sugar, .saturatedFat, .sodium]) {
                        NutrientField(kind: $0, nutrients: $item.nutrients)
                    }
                }
            }
            .navigationTitle("Edit Item")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(item); Haptics.success(); dismiss() }
                }
            }
        }
    }
}
