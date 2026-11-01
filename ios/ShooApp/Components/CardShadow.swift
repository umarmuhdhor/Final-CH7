import SwiftUI

extension View {
    /// Figma's shared card shadow ("Update card", "Card Akun", "Evidence Card", "Verified Note"…):
    /// #F6FCFE 5% y 1 blur 2, then #E7F2F6 6% y 6 blur 16. SwiftUI radius is half the Figma blur.
    func figmaCardShadow() -> some View {
        shadow(color: Color(hex: 0xF6FCFE, opacity: 0.05), radius: 1, y: 1)
            .shadow(color: Color(hex: 0xE7F2F6, opacity: 0.06), radius: 8, y: 6)
    }
}
