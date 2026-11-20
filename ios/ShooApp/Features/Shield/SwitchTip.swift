import SwiftUI

/// The one-time tip at Home's ⇆ (Figma 2368:13263, Alief's reference): ⇆ only appears once this iPhone has been
/// Guardian, so the first arrival at Guardian Home points at it. A white card right under ⇆ with a small pointer, a
/// teal tile with a white ⇆, "Pindah mode di sini" and what it does. No dim and no timer: it stays until a tap anywhere.
/// Placed in the top bar's frame: ⇆ is a 50 pt circle 24 pt from the left, right under the status bar (`HomeTopBar`).
struct SwitchTip: View {
    let onClose: () -> Void
    @Environment(\.locale) private var locale

    /// Figma: the pointer 1 pt under the 50 pt circle, the card 11 pt under it, 16 pt from the screen's edge.
    private static let pointerTop: CGFloat = 51
    private static let cardLeading: CGFloat = 16
    /// The circle's centre, 24 + 25 from the edge, in the card's frame.
    private static let pointerCentre: CGFloat = 24 + 25 - cardLeading

    private var language: AppLanguage { AppLanguage(locale: locale) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Triangle()
                .fill(.white)
                .frame(width: 22, height: 11)
                .padding(.leading, Self.pointerCentre - 11)
            HStack(spacing: 14) {
                Image("HomeSwitch")
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: 24, height: 24)
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(
                        LinearGradient(colors: [Color(red: 0.42, green: 0.78, blue: 0.79), Color(red: 0.24, green: 0.60, blue: 0.64)],
                                       startPoint: .top, endPoint: .bottom),
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                    )
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Switch modes here")
                        .onboardingFont(17, weight: .bold, relativeTo: .headline)
                        .foregroundStyle(Color(red: 0.10, green: 0.17, blue: 0.27))
                    Text("Move between Personal (just you) and Guardian (your family) any time.")
                        .onboardingFont(15, relativeTo: .subheadline)
                        .foregroundStyle(HomeTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 266, alignment: .leading)
            }
            .padding(14)
            .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: Color(red: 0, green: 0.1, blue: 0.15).opacity(0.18), radius: 24, y: 8)
            // Figma: the card 11 pt under the circle, so 10 under the pointer's tip after its 11 pt.
            .padding(.top, -1)
        }
        .environment(\.colorScheme, .light)
        .padding(.top, Self.pointerTop)
        .padding(.leading, Self.cardLeading)
        .padding(.trailing, 16)
        .onTapGesture(perform: onClose)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text("Double-tap to close"))
        .accessibilityAction(.escape, onClose)
        .accessibilityIdentifier("home.switchTip")
        .onAppear {
            AccessibilityNotification.Announcement(
                "\(L10n.string("Switch modes here", language: language)). "
                    + L10n.string("Move between Personal (just you) and Guardian (your family) any time.", language: language)
            ).post()
        }
    }
}

/// The tip's pointer, tip up.
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

#Preview {
    ZStack(alignment: .topLeading) {
        Color.teal.ignoresSafeArea()
        SwitchTip {}
    }
}
