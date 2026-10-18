import SwiftUI

/// Brand colors shared by the app and widgets.
/// Deep "ink" surfaces with citrus / coral / mint accents for the three macros.
enum Palette {
    static let ink = Color(red: 0.05, green: 0.06, blue: 0.10)
    static let inkRaised = Color(red: 0.10, green: 0.11, blue: 0.17)
    static let calories = Color(red: 1.00, green: 0.47, blue: 0.29)   // ember
    static let protein = Color(red: 0.36, green: 0.86, blue: 0.67)    // mint
    static let carbs = Color(red: 1.00, green: 0.80, blue: 0.25)      // citrus
    static let fat = Color(red: 0.62, green: 0.52, blue: 1.00)        // violet
    static let water = Color(red: 0.30, green: 0.72, blue: 1.00)
    static let fiber = Color(red: 0.55, green: 0.80, blue: 0.35)
    static let warning = Color(red: 1.00, green: 0.36, blue: 0.42)

    static let calorieGradient = AngularGradient(
        colors: [calories, Color(red: 1.0, green: 0.30, blue: 0.50), carbs, calories],
        center: .center
    )
}
