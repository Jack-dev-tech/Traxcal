import SwiftUI

/// Animated progress ring with gradient stroke, glow and over-goal overlap.
struct RingGauge: View {
    var progress: Double
    var lineWidth: CGFloat = 18
    var gradient: AngularGradient = Palette.calorieGradient
    var trackColor: Color = .white.opacity(0.08)

    @State private var animated: Double = 0

    var body: some View {
        ZStack {
            Circle().stroke(trackColor, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(animated, 1))
                .stroke(gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: Palette.calories.opacity(0.5), radius: 10)
            if animated > 1 {
                Circle()
                    .trim(from: 0, to: min(animated - 1, 1))
                    .stroke(Palette.warning, style: StrokeStyle(lineWidth: lineWidth * 0.55, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .onAppear { withAnimation(.spring(response: 1.1, dampingFraction: 0.8).delay(0.1)) { animated = progress } }
        .onChange(of: progress) { _, new in withAnimation(Theme.spring) { animated = new } }
    }
}

/// Horizontal macro progress bar with label and animated fill.
struct MacroBar: View {
    var title: String
    var value: Double
    var goal: Double
    var unit: String = "g"
    var color: Color

    @State private var fill: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Int(value.rounded()))")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .contentTransition(.numericText(value: value))
                Text("/ \(Int(goal.rounded()))\(unit)").font(.caption).foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.08))
                    Capsule()
                        .fill(LinearGradient(colors: [color.opacity(0.7), color], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(geo.size.width * min(fill, 1), fill > 0 ? 8 : 0))
                        .shadow(color: color.opacity(0.6), radius: 6)
                }
            }
            .frame(height: 10)
        }
        .onAppear { withAnimation(Theme.spring.delay(0.2)) { fill = goal > 0 ? value / goal : 0 } }
        .onChange(of: value) { _, v in withAnimation(Theme.spring) { fill = goal > 0 ? v / goal : 0 } }
    }
}

/// Compact circular macro gauge used on cards and widgets.
struct MiniRing: View {
    var title: String
    var value: Double
    var goal: Double
    var color: Color

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RingGauge(
                    progress: goal > 0 ? value / goal : 0, lineWidth: 7,
                    gradient: AngularGradient(colors: [color.opacity(0.6), color], center: .center)
                )
                Text("\(Int(value.rounded()))")
                    .font(.system(.footnote, design: .rounded).weight(.bold))
                    .contentTransition(.numericText(value: value))
            }
            .frame(width: 54, height: 54)
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
        }
    }
}

struct SourceBadge: View {
    var source: FoodSource

    var body: some View {
        Label(source.label, systemImage: source.symbol)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.18), in: .capsule)
            .foregroundStyle(color)
    }

    private var color: Color {
        switch source {
        case .usda: Palette.protein
        case .openFoodFacts, .barcode: Palette.water
        case .restaurant: Palette.calories
        case .chipotle: Color(red: 0.75, green: 0.25, blue: 0.15)
        case .generic: Palette.fiber
        case .custom: .gray
        case .ai: Palette.fat
        }
    }
}

struct SectionTitle: View {
    var title: String
    var symbol: String?
    var trailing: AnyView? = nil

    var body: some View {
        HStack {
            if let symbol { Image(systemName: symbol).foregroundStyle(Palette.calories) }
            Text(title).font(.title3.weight(.bold))
            Spacer()
            trailing
        }
        .padding(.horizontal, 4)
    }
}

/// Inline macro summary like "P 32 · C 40 · F 12".
struct MacroLine: View {
    var nutrients: Nutrients

    var body: some View {
        HStack(spacing: 10) {
            tag("P", nutrients.protein, Palette.protein)
            tag("C", nutrients.carbs, Palette.carbs)
            tag("F", nutrients.fat, Palette.fat)
        }
        .font(.caption.weight(.semibold).monospacedDigit())
    }

    private func tag(_ letter: String, _ value: Double, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(letter) \(Int(value.rounded()))g").foregroundStyle(.secondary)
        }
    }
}

/// Shimmering placeholder used while AI is thinking.
struct ShimmerView: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(.white.opacity(0.06))
            .overlay {
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, .white.opacity(0.18), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.6)
                        .offset(x: phase * geo.size.width)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .onAppear {
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1.4 }
            }
    }
}

/// A stepper-like control for servings with haptics on each change.
struct ServingStepper: View {
    @Binding var value: Double
    var step: Double = 0.5

    var body: some View {
        HStack(spacing: 0) {
            button("minus") { value = max(step, value - step) }
            Text(value.formatted(.number.precision(.fractionLength(0...2))))
                .font(.display(28))
                .contentTransition(.numericText(value: value))
                .frame(minWidth: 70)
            button("plus") { value += step }
        }
        .sensoryFeedback(.selection, trigger: value)
        .animation(Theme.bouncy, value: value)
    }

    private func button(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.headline)
                .frame(width: 44, height: 44)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.pressable)
    }
}
