import SwiftUI

extension View {
    /// Figma's shared card shadow ("Update card", "Card Akun", "Evidence Card", "Verified Note"…):
    /// #F6FCFE 5% y 1 blur 2, then #E7F2F6 6% y 6 blur 16. SwiftUI radius is half the Figma blur.
    func figmaCardShadow() -> some View {
        shadow(color: Color(hex: 0xF6FCFE, opacity: 0.05), radius: 1, y: 1)
            .shadow(color: Color(hex: 0xE7F2F6, opacity: 0.06), radius: 8, y: 6)
    }

    /// Figma's white capsule button shadow ("Aman", "Bahaya" secondary): black 20%, y 3, blur 5,
    /// spread -3. SwiftUI has no spread, so a capsule inset by 3 pt casts it behind the button.
    func figmaButtonShadow() -> some View {
        background {
            Capsule()
                .fill(.white)
                .padding(3)
                .shadow(color: .black.opacity(0.2), radius: 2.5, y: 3)
        }
    }
}
