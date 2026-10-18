import SwiftUI

/// Manual entry: name + calories + optional macros and micros.
struct QuickAddView: View {
    var onDone: () -> Void

    @Environment(FoodLogger.self) private var logger
    @State private var name = ""
    @State private var nutrients = Nutrients()
    @State private var meal: MealType = .suggested()
    @State private var showMicros = false

    var body: some View {
        Form {
            Section("Food") {
                TextField("Name (e.g. Homemade lasagna)", text: $name)
                Picker("Meal", selection: $meal) {
                    ForEach(MealType.allCases) { Text($0.title).tag($0) }
                }
            }
            Section("Macros") {
                NutrientField(kind: .calories, nutrients: $nutrients)
                NutrientField(kind: .protein, nutrients: $nutrients)
                NutrientField(kind: .carbs, nutrients: $nutrients)
                NutrientField(kind: .fat, nutrients: $nutrients)
                if nutrients.calories == 0 && nutrients.macroCalories > 0 {
                    Button("Use \(Int(nutrients.macroCalories)) kcal from macros") {
                        nutrients.calories = nutrients.macroCalories.rounded()
                        Haptics.tap()
                    }
                }
            }
            Section {
                DisclosureGroup("More nutrients", isExpanded: $showMicros) {
                    ForEach(NutrientKind.micros) { NutrientField(kind: $0, nutrients: $nutrients) }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Quick Add")
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: "Log \(Int(nutrients.calories)) kcal", symbol: "bolt.fill", color: Palette.carbs) {
                let item = FoodItem(
                    id: "custom-\(UUID().uuidString)", name: name.isEmpty ? "Quick Add" : name, brand: nil,
                    source: .custom, servingDescription: "1 serving", servingGrams: nil, nutrients: nutrients
                )
                logger.log(item, servings: 1, meal: meal)
                Haptics.celebrate()
                onDone()
            }
            .disabled(nutrients.calories <= 0)
            .opacity(nutrients.calories <= 0 ? 0.5 : 1)
            .padding()
        }
    }
}

/// A numeric field bound to one nutrient. Empty means "not reported" for micronutrients.
struct NutrientField: View {
    var kind: NutrientKind
    @Binding var nutrients: Nutrients

    var body: some View {
        HStack {
            Circle().fill(Theme.color(for: kind)).frame(width: 8, height: 8)
            Text(kind.title)
            Spacer()
            TextField("0", value: binding, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
            Text(kind.unit).foregroundStyle(.secondary).frame(width: 34, alignment: .leading)
        }
    }

    private var binding: Binding<Double?> {
        Binding(
            get: {
                let v = nutrients.value(kind)
                return (v == 0 && [.calories, .protein, .carbs, .fat].contains(kind)) ? nil : v
            },
            set: { nutrients.set(kind, $0) }
        )
    }
}
