import SwiftUI

extension ShapeStyle where Self == Color {
    /// Secondary text that still reaches 4.5:1 (WCAG 1.4.3) on white and grouped cards.
    /// `.secondary` is about 3.5:1 in light mode, too faint for Shoo's 45–65 audience.
    static var readableSecondary: Color { Color(.label).opacity(0.72) }
}
