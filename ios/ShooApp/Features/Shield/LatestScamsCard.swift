import SwiftUI

/// Figma "Frame 1618872186" (Pribadi/Home 1115:13601, protected/Home 1115:17238): the newest scam cases among Shoo
/// users. A red shield and the title (SF Pro Rounded 17, #6A717E), 16 pt, then the cases as 96 pt cards two to a
/// row, 8 apart; more than two scroll sideways.
struct LatestScamsCard: View {
    let cases: [ScamCase]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Figma "Header": the symbol (SF Pro Semibold 16, #E5483B) 8 left of the title, 22 pt line.
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(HomeTheme.tileIcon)
                    .frame(width: 18)
                    .accessibilityHidden(true)
                Text("Latest scams among Shoo users")
                    .onboardingFont(17, design: .rounded, tracking: -0.17, relativeTo: .body)
                    .figmaLineHeight(22, relativeTo: .body)
                    .foregroundStyle(OnboardingTheme.bodyInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
            }
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 8) {
                    ForEach(cases) { ScamCaseCard(scamCase: $0) }
                }
            } else {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(cases) { scamCase in
                            ScamCaseCard(scamCase: scamCase)
                                .containerRelativeFrame(.horizontal, count: 2, spacing: 8)
                        }
                    }
                    // Every card as tall as the tallest.
                    .fixedSize(horizontal: false, vertical: true)
                    .scrollTargetLayout()
                    // Room for the cards' shadow inside the clip.
                    .padding(.vertical, 8)
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned)
                .padding(.vertical, -8)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.scamCases")
    }
}

/// Figma "Update card" (1115:17243): white, 12 pt corners, a 1 pt #E7E9ED ring, 12 pt padding (22 on the right); the case in
/// SF Pro Rounded 17 (22 pt lines, #191D2F), then when and where in 13 (18 pt, #564C51), 8 under it.
private struct ScamCaseCard: View {
    let scamCase: ScamCase

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: scamCase.title)
                .onboardingFont(17, design: .rounded, tracking: -0.17, relativeTo: .body)
                .figmaLineHeight(22, relativeTo: .body)
                .foregroundStyle(HomeTheme.navy)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Text(verbatim: scamCase.detail)
                .onboardingFont(13, design: .rounded, tracking: -0.08, relativeTo: .footnote)
                .figmaLineHeight(18, glyphOffset: 1, relativeTo: .footnote)
                .foregroundStyle(HomeTheme.rowSubtitle)
        }
        // Figma: the text 139 wide, 12 from the left and 22 from the right.
        .padding(.leading, 12)
        .padding(.trailing, 22)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 96, maxHeight: .infinity, alignment: .topLeading)
        .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color(hex: 0xE7E9ED), lineWidth: 1))
        .figmaCardShadow()
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    LatestScamsCard(cases: MockScenarios.scamCases)
        .padding(24)
}
