import SwiftUI

extension ShapeStyle where Self == Color {
    /// Secondary text that still reaches 4.5:1 (WCAG 1.4.3) on white and grouped cards.
    /// `.secondary` is about 3.5:1 in light mode, too faint for Shoo's 45–65 audience.
    static var readableSecondary: Color { Color(.label).opacity(0.72) }
}

extension Color {
    /// Error and destructive text that reaches 4.5:1 in light and dark mode (system red is about 3.6:1).
    static let readableRed = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1, green: 0.54, blue: 0.50, alpha: 1)
            : UIColor(red: 0.70, green: 0.15, blue: 0.12, alpha: 1)
    })
}
