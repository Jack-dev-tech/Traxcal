import SwiftUI

struct SettingsView: View {
    @Environment(GoalStore.self) private var goals
    @Environment(HealthKitService.self) private var health
    @Environment(AIRouter.self) private var ai
    @AppStorage("search.live") private var liveSearch = true
    @State private var usdaKey = KeychainStore.get(.usdaAPIKey) ?? ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink { GoalsView() } label: {
                        row("Goals & Profile", "\(Int(goals.goal(.calories))) kcal · P\(Int(goals.goal(.protein))) C\(Int(goals.goal(.carbs))) F\(Int(goals.goal(.fat)))", "target", Palette.calories)
                    }
                }

                Section {
                    NavigationLink { AISettingsView() } label: {
                        row("AI Assistant", ai.backend.title, "sparkles", Palette.fat)
                    }
                } footer: {
                    Text("Powers meal photo scanning, describing meals, and AI trends. Choose on-device models for privacy or connect a cloud provider with your own API key.")
                }

                Section("Apple Health") {
                    if HealthKitService.isAvailable {
                        Toggle(isOn: Binding(
                            get: { health.isEnabled },
                            set: { on in
                                if on { Task { await health.requestAuthorization() } } else { health.isEnabled = false }
                            }
                        )) {
                            row("Sync with Health", "Food, macros, micros & water", "heart.fill", .pink)
                        }
                        if health.isEnabled {
                            LabeledContent("Active energy today", value: "\(Int(health.activeEnergyToday)) kcal")
                            if let w = health.latestWeightKg {
                                LabeledContent("Latest weight", value: goals.profile.useMetric ? "\(w.formatted(.number.precision(.fractionLength(1)))) kg" : "\(Int(w * 2.2046)) lb")
                            }
                        }
                    } else {
                        Text("Apple Health isn't available on this device.").foregroundStyle(.secondary)
                    }
                }

                Section {
                    Toggle(isOn: $liveSearch) {
                        row("Live food databases", "USDA FoodData Central + Open Food Facts", "network", Palette.protein)
                    }
                    SecureField("USDA API key (optional)", text: $usdaKey)
                        .onSubmit { KeychainStore.set(usdaKey, for: .usdaAPIKey) }
                        .onChange(of: usdaKey) { _, v in KeychainStore.set(v, for: .usdaAPIKey) }
                    Link("Get a free USDA key", destination: URL(string: "https://fdc.nal.usda.gov/api-key-signup")!)
                } header: {
                    Text("Food Search")
                } footer: {
                    Text("Search checks live databases first and falls back to Traxcal's built-in restaurant menus (Chipotle, McDonald's, Shake Shack, Chick-fil-A and more) when offline. Without a key USDA uses a shared, rate-limited demo key.")
                }

                Section("Units") {
                    Toggle("Metric units", isOn: Binding(get: { goals.profile.useMetric }, set: { goals.profile.useMetric = $0 }))
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    Text("Nutrition values for restaurants are approximations based on publicly posted information and AI estimates can be inaccurate. Traxcal is not a medical device.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Replay Onboarding") { goals.hasOnboarded = false }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Settings")
        }
    }

    private func row(_ title: String, _ subtitle: String, _ symbol: String, _ color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(color.gradient, in: .rect(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

struct GoalsView: View {
    @Environment(GoalStore.self) private var goals

    var body: some View {
        @Bindable var goals = goals
        Form {
            Section("Profile") {
                TextField("Name", text: $goals.profile.name)
                Picker("Sex", selection: $goals.profile.sex) {
                    ForEach(UserProfile.Sex.allCases) { Text($0.rawValue.capitalized).tag($0) }
                }
                Stepper("Age: \(goals.profile.age)", value: $goals.profile.age, in: 13...100)
                if goals.profile.useMetric {
                    Stepper("Height: \(Int(goals.profile.heightCm)) cm", value: $goals.profile.heightCm, in: 120...230)
                    Stepper("Weight: \(goals.profile.weightKg.formatted(.number.precision(.fractionLength(1)))) kg", value: $goals.profile.weightKg, in: 35...250, step: 0.5)
                } else {
                    let inches = Int((goals.profile.heightCm / 2.54).rounded())
                    Stepper("Height: \(inches / 12)′ \(inches % 12)″", value: Binding(get: { goals.profile.heightCm / 2.54 }, set: { goals.profile.heightCm = $0 * 2.54 }), in: 48...90, step: 1)
                    Stepper("Weight: \(Int((goals.profile.weightKg * 2.2046).rounded())) lb", value: Binding(get: { goals.profile.weightKg * 2.2046 }, set: { goals.profile.weightKg = $0 / 2.2046 }), in: 80...550, step: 1)
                }
                Picker("Activity", selection: $goals.profile.activity) {
                    ForEach(UserProfile.Activity.allCases) { Text($0.title).tag($0) }
                }
                Picker("Goal", selection: $goals.profile.objective) {
                    ForEach(UserProfile.Objective.allCases) { Text($0.title).tag($0) }
                }
            }

            Section {
                LabeledContent("BMR", value: "\(Int(goals.profile.bmr)) kcal")
                LabeledContent("Maintenance (TDEE)", value: "\(Int(goals.profile.tdee)) kcal")
                Button("Recalculate goals from profile", systemImage: "wand.and.stars") {
                    withAnimation { goals.applySuggestedGoals() }
                    Haptics.success()
                }
            }

            Section("Daily Targets") {
                ForEach(NutrientKind.allCases) { kind in
                    HStack {
                        Circle().fill(Theme.color(for: kind)).frame(width: 8, height: 8)
                        Text(kind.title)
                        if kind.isLimit { Text("limit").font(.caption2).foregroundStyle(.secondary) }
                        Spacer()
                        TextField("", value: Binding(get: { goals.goal(kind) }, set: { goals.goals[kind] = $0 }), format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text(kind.unit).foregroundStyle(.secondary).frame(width: 34, alignment: .leading)
                    }
                }
                Stepper("Water: \(Int(goals.waterGoalML)) ml", value: $goals.waterGoalML, in: 500...6000, step: 250)
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Goals")
    }
}
