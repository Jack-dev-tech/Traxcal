import SwiftUI

enum Theme {
    static let corner: CGFloat = 26
    static let smallCorner: CGFloat = 16
    static let spacing: CGFloat = 16
    static let spring = Animation.spring(response: 0.45, dampingFraction: 0.78)
    static let bouncy = Animation.spring(response: 0.38, dampingFraction: 0.62)

    static func color(for kind: NutrientKind) -> Color {
        switch kind {
        case .calories: Palette.calories
        case .protein: Palette.protein
        case .carbs: Palette.carbs
        case .fat: Palette.fat
        case .fiber: Palette.fiber
        case .sodium, .saturatedFat, .cholesterol: Palette.warning
        case .sugar: Color.pink
        case .caffeine: Color.brown
        default: Palette.water
        }
    }
}

extension Font {
    /// Rounded, heavy display numerals are a signature of the Traxcal look.
    static func display(_ size: CGFloat, weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

extension View {
    /// Standard Liquid Glass card used throughout the app.
    func glassCard(cornerRadius: CGFloat = Theme.corner, padding: CGFloat = Theme.spacing, tint: Color? = nil) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(tint.map { Glass.regular.tint($0.opacity(0.18)) } ?? Glass.regular, in: .rect(cornerRadius: cornerRadius))
    }

    /// Fades and lifts content in when it first appears, staggered by `index`.
    func appearAnimation(index: Int = 0) -> some View {
        modifier(AppearModifier(delay: Double(index) * 0.06))
    }
}

private struct AppearModifier: ViewModifier {
    let delay: Double
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 18)
            .scaleEffect(visible ? 1 : 0.97)
            .onAppear {
                withAnimation(Theme.spring.delay(delay)) { visible = true }
            }
    }
}

/// Animated mesh-gradient backdrop that slowly drifts; the app's distinctive canvas.
struct AuroraBackground: View {
    var accent: Color = Palette.calories

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let s = Float(sin(t / 4)) * 0.12
            let c = Float(cos(t / 5)) * 0.12
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0, 0], [0.5 + s, 0], [1, 0],
                    [0, 0.5 + c], [0.5 - c, 0.5 + s], [1, 0.5 - s],
                    [0, 1], [0.5 + c, 1], [1, 1],
                ],
                colors: [
                    Palette.ink, accent.opacity(0.55), Palette.ink,
                    Palette.fat.opacity(0.35), Palette.inkRaised, Palette.protein.opacity(0.25),
                    Palette.ink, Palette.ink, Palette.inkRaised,
                ]
            )
        }
        .ignoresSafeArea()
    }
}

/// Press-down scale + haptic button style.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.94

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(Theme.bouncy, value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed) { _, pressed in pressed }
    }
}

extension ButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle { PressableStyle() }
}

/// Prominent gradient call-to-action.
struct PrimaryButton: View {
    var title: String
    var symbol: String?
    var color: Color = Palette.calories
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let symbol { Image(systemName: symbol) }
                Text(title)
            }
            .font(.headline)
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(colors: [color, color.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: .capsule
            )
            .shadow(color: color.opacity(0.45), radius: 14, y: 6)
        }
        .buttonStyle(.pressable)
    }
}
