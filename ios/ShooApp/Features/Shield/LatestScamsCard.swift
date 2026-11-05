import SwiftUI

/// Figma "Kartu/Scam Terbaru" 955:10323: the newest scam cases among Shoo users, one under the other.
struct LatestScamsCard: View {
    let cases: [ScamCase]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(HomeTheme.tileIcon)
                    .frame(width: 34, height: 34)
                    .background(HomeTheme.scamIconFill, in: Circle())
                    .accessibilityHidden(true)
                Text("Latest scams among Shoo users")
                    .onboardingFont(17, weight: .semibold, relativeTo: .headline)
                    .foregroundStyle(HomeTheme.navy)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
            }
            ForEach(Array(cases.enumerated()), id: \.element.id) { index, scamCase in
                if index > 0 {
                    Rectangle().fill(HomeTheme.stepDivider).frame(height: 1).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: scamCase.title)
                        .onboardingFont(17, design: .rounded, relativeTo: .body)
                        .tracking(-0.17)
                        .foregroundStyle(HomeTheme.navy)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: scamCase.detail)
                        .onboardingFont(13, design: .rounded, relativeTo: .footnote)
                        .tracking(-0.08)
                        .foregroundStyle(HomeTheme.secondaryInk)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        // Figma: #1A3861 7 %, y 6, blur 18.
        .shadow(color: Color(red: 0x1A / 255, green: 0x38 / 255, blue: 0x61 / 255).opacity(0.07), radius: 9, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.scamCases")
    }
}

#Preview {
    LatestScamsCard(cases: MockScenarios.scamCases)
        .padding(24)
}
