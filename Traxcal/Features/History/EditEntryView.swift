import SwiftUI

/// Edits a logged entry on a draft copy; changes are applied (and synced to Health) on Save.
struct EditEntryView: View {
    let entry: FoodEntry

    @Environment(\.dismiss) private var dismiss
    @Environment(FoodLogger.self) private var logger
    @State private var name: String
    @State private var brand: String
    @State private var meal: MealType
    @State private var date: Date
    @State private var servings: Double
    @State private var servingDescription: String
    @State private var perServing: Nutrients
    @State private var notes: String
    @State private var confirmDelete = false

    init(entry: FoodEntry) {
        self.entry = entry
        _name = State(initialValue: entry.name)
        _brand = State(initialValue: entry.brand ?? "")
        _meal = State(initialValue: entry.meal)
        _date = State(initialValue: entry.date)
        _servings = State(initialValue: entry.servings)
        _servingDescription = State(initialValue: entry.servingDescription)
        _perServing = State(initialValue: entry.perServing)
        _notes = State(initialValue: entry.notes)
    }

    private var total: Nutrients { perServing.scaled(by: servings) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    MacroDonut(nutrients: total).frame(height: 170).listRowBackground(Color.clear)
                }
                Section("Food") {
                    TextField("Name", text: $name)
                    TextField("Brand / Restaurant", text: $brand)
                    LabeledContent("Source") { SourceBadge(source: entry.source) }
                }
                Section("When") {
                    Picker("Meal", selection: $meal) {
                        ForEach(MealType.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                    DatePicker("Time", selection: $date)
                }
                Section("Portion") {
                    TextField("Serving", text: $servingDescription)
                    HStack {
                        Text("Servings")
                        Spacer()
                        ServingStepper(value: $servings, step: 0.25)
                    }
                }
                Section {
                    ForEach(NutrientKind.allCases) { NutrientField(kind: $0, nutrients: $perServing) }
                } header: {
                    Text("Nutrition per serving")
                } footer: {
                    Text("Totals: \(Int(total.calories)) kcal · P \(Int(total.protein))g · C \(Int(total.carbs))g · F \(Int(total.fat))g")
                }
                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                }
                Section {
                    Button("Delete Entry", systemImage: "trash", role: .destructive) { confirmDelete = true }
                }
            }
            .navigationTitle("Edit Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.fontWeight(.bold) }
            }
            .confirmationDialog("Delete \(entry.displayName)?", isPresented: $confirmDelete) {
                Button("Delete", role: .destructive) {
                    logger.delete(entry)
                    Haptics.warning()
                    dismiss()
                }
            }
        }
    }

    private func save() {
        entry.name = name
        entry.brand = brand.isEmpty ? nil : brand
        entry.meal = meal
        entry.date = date
        entry.servings = servings
        entry.servingDescription = servingDescription
        entry.perServing = perServing
        entry.notes = notes
        logger.didEdit(entry)
        Haptics.success()
        dismiss()
    }
}
