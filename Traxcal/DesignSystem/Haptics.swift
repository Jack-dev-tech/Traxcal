import UIKit

/// Centralized haptics so every interaction feels consistent.
/// SwiftUI views generally prefer `.sensoryFeedback`; this is for imperative call sites.
@MainActor
enum Haptics {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let soft = UIImpactFeedbackGenerator(style: .soft)
    private static let selectionGenerator = UISelectionFeedbackGenerator()
    private static let notification = UINotificationFeedbackGenerator()

    static func tap() { light.impactOccurred() }
    static func press() { medium.impactOccurred(intensity: 0.8) }
    static func thud() { rigid.impactOccurred() }
    static func selection() { selectionGenerator.selectionChanged() }
    static func success() { notification.notificationOccurred(.success) }
    static func warning() { notification.notificationOccurred(.warning) }
    static func error() { notification.notificationOccurred(.error) }

    /// A short rising "ta-da" used when a food is logged or a goal is hit.
    static func celebrate() {
        soft.impactOccurred(intensity: 0.5)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { medium.impactOccurred(intensity: 0.8) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { notification.notificationOccurred(.success) }
    }
}
