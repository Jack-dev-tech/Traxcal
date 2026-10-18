import SwiftUI

/// Animated first-run flow: welcome → profile → goals reveal → Apple Health → AI choice.
struct OnboardingView: View {
    @Environment(GoalStore.self) private var goals
    @Environment(HealthKitService.self) private var health
    @Environment(AIRouter.self) private var ai
    @Environment(LocalModelManager.self) private var models
    @State private var step = 0
    @State private var profile = UserProfile()

    private let steps = 5

    var body: some View {
        ZStack {
            AuroraBackground(accent: [Palette.calories, Palette.protein, Palette.carbs, Palette.water, Palette.fat][step % 5])
                .animation(.easeInOut(duration: 0.8), value: step)

            VStack(spacing: 0) {
                progress.padding(.top, 12)
                TabView(selection: $step) {
                    welcome.tag(0)
                    profileStep.tag(1)
                    goalsStep.tag(2)
                    healthStep.tag(3)
                    aiStep.tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(Theme.spring, value: step)

                PrimaryButton(title: step == steps - 1 ? "Start Tracking" : "Continue", symbol: step == steps - 1 ? "checkmark" : "arrow.right") {
                    advance()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
        }
        .sensoryFeedback(.selection, trigger: step)
        .onAppear { profile = goals.profile }
    }

    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(0..<steps, id: \.self) { i in
                Capsule()
                    .fill(i <= step ? Palette.calories : .white.opacity(0.15))
                    .frame(width: i == step ? 28 : 10, height: 6)
                    .animation(Theme.bouncy, value: step)
            }
        }
    }

    private func advance() {
        if step == 1 {
            goals.profile = profile
            goals.applySuggestedGoals()
        }
        if step < steps - 1 {
            withAnimation(Theme.spring) { step += 1 }
        } else {
            goals.profile = profile
            Haptics.celebrate()
            goals.hasOnboarded = true
        }
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                RingGauge(progress: 0.72, lineWidth: 26).frame(width: 200, height: 200)
                Image(systemName: "flame.fill").font(.system(size: 64)).foregroundStyle(Palette.calories).symbolEffect(.breathe)
            }
            Text("Traxcal").font(.display(48))
            Text("Track calories, macros and nutrients with AI photo scanning, every major restaurant in one search, and Apple Health sync.")
                .font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 32)
            Spacer()
        }
    }

    private var profileStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("About you").font(.display(34))
                Text("Used to calculate your daily calorie and macro targets.").foregroundStyle(.secondary)
                TextField("First name", text: $profile.name).padding(14).glassEffect(.regular, in: .rect(cornerRadius: 16))
                Picker("Sex", selection: $profile.sex) {
                    ForEach(UserProfile.Sex.allCases) { Text($0.rawValue.capitalized).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Metric units", isOn: $profile.useMetric)
                VStack(spacing: 12) {
                    Stepper("Age: \(profile.age)", value: $profile.age, in: 13...100)
                    if profile.useMetric {
                        Stepper("Height: \(Int(profile.heightCm)) cm", value: $profile.heightCm, in: 120...230)
                        Stepper("Weight: \(Int(profile.weightKg)) kg", value: $profile.weightKg, in: 35...250)
                    } else {
                        let inches = Int((profile.heightCm / 2.54).rounded())
                        Stepper("Height: \(inches / 12)′ \(inches % 12)″", value: Binding(get: { profile.heightCm / 2.54 }, set: { profile.heightCm = $0 * 2.54 }), in: 48...90)
                        Stepper("Weight: \(Int((profile.weightKg * 2.2046).rounded())) lb", value: Binding(get: { profile.weightKg * 2.2046 }, set: { profile.weightKg = $0 / 2.2046 }), in: 80...550)
                    }
                }
                .glassCard()
                Text("Activity").font(.headline)
                ForEach(UserProfile.Activity.allCases) { level in
                    choice(level.title, selected: profile.activity == level) { profile.activity = level }
                }
                Text("Goal").font(.headline)
                HStack {
                    ForEach(UserProfile.Objective.allCases) { o in
                        choice(o.title, selected: profile.objective == o) { profile.objective = o }
                    }
                }
            }
            .padding(24)
        }
    }

    private var goalsStep: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("Your daily targets").font(.display(32))
            ZStack {
                RingGauge(progress: 1, lineWidth: 22).frame(width: 190, height: 190)
                VStack(spacing: 0) {
                    Text("\(Int(goals.goal(.calories)))").font(.display(44)).contentTransition(.numericText())
                    Text("kcal / day").font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 22) {
                MiniRing(title: "Protein", value: goals.goal(.protein), goal: goals.goal(.protein), color: Palette.protein)
                MiniRing(title: "Carbs", value: goals.goal(.carbs), goal: goals.goal(.carbs), color: Palette.carbs)
                MiniRing(title: "Fat", value: goals.goal(.fat), goal: goals.goal(.fat), color: Palette.fat)
            }
            Text("Based on a maintenance of \(Int(goals.profile.tdee)) kcal. You can fine-tune every nutrient in Settings.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 32)
            Spacer()
        }
    }

    private var healthStep: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "heart.text.square.fill").font(.system(size: 80)).foregroundStyle(.pink).symbolEffect(.pulse)
            Text("Sync with Apple Health").font(.display(30)).multilineTextAlignment(.center)
            Text("Save every meal's calories, macros, vitamins and water to Health, and use your workouts to adjust your daily budget.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 32)
            if health.isEnabled {
                Label("Connected", systemImage: "checkmark.circle.fill").font(.headline).foregroundStyle(Palette.protein)
                    .transition(.scale.combined(with: .opacity))
            } else if HealthKitService.isAvailable {
                Button("Connect Apple Health") {
                    Task {
                        if await health.requestAuthorization() { Haptics.success() }
                    }
                }
                .buttonStyle(.glassProminent)
                .tint(.pink)
            }
            Spacer()
        }
        .animation(Theme.spring, value: health.isEnabled)
    }

    private var aiStep: some View {
        let recommended = LocalModelCatalog.recommended()
        let apple = AppleIntelligenceProvider.availability
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "sparkles").font(.system(size: 54)).foregroundStyle(Palette.fat).symbolEffect(.bounce, value: step)
                Text("Choose your AI").font(.display(32))
                Text("AI powers photo scanning and personalized trends. You can change this any time.").foregroundStyle(.secondary)

                if apple.available {
                    aiOption("Apple Intelligence", "Built in, private, nothing to download.", "apple.intelligence",
                             selected: ai.backend == .appleIntelligence) { ai.backend = .appleIntelligence }
                }
                aiOption("On-device: \(recommended.name)",
                         "Recommended for your iPhone (\(DeviceCapability.current.marketingRAM) RAM). \(recommended.downloadGB.formatted(.number.precision(.fractionLength(1)))) GB download, works offline.",
                         "cpu", selected: ai.backend == .onDevice(modelID: recommended.id)) {
                    ai.backend = .onDevice(modelID: recommended.id)
                    if models.state(recommended) != .downloaded { models.download(recommended) }
                }
                if case .downloading(let p) = models.state(recommended) {
                    ProgressView(value: p) { Text("Downloading \(recommended.name)… keep Traxcal open") }.tint(Palette.fat)
                }
                aiOption("Cloud provider", "Use your own key for ChatGPT, Claude, Gemini, DeepSeek, Qwen and more — set it up in Settings → AI.",
                         "cloud.fill", selected: { if case .cloud = ai.backend { return true }; return false }()) {}
                aiOption("Skip for now", "Search, restaurant menus and the Chipotle builder work without AI.", "forward.fill",
                         selected: ai.backend == .none) { ai.backend = .none }
            }
            .padding(24)
        }
    }

    // MARK: Helpers

    private func choice(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(Theme.bouncy) { action() }
            Haptics.selection()
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .foregroundStyle(selected ? .black : .primary)
                .background(selected ? AnyShapeStyle(Palette.calories) : AnyShapeStyle(.white.opacity(0.06)), in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.pressable)
    }

    private func aiOption(_ title: String, _ subtitle: String, _ symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(Theme.bouncy) { action() }
            Haptics.selection()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: UIImage(systemName: symbol) == nil ? "cpu" : symbol)
                    .font(.title2).foregroundStyle(Palette.fat).frame(width: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Palette.protein : .secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(16)
            .glassEffect(selected ? Glass.regular.tint(Palette.fat.opacity(0.3)).interactive() : Glass.regular.interactive(), in: .rect(cornerRadius: 20))
        }
        .buttonStyle(.pressable)
    }
}
