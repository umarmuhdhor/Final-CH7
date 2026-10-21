import SwiftUI

/// Risk score 0–100 as a ring with the percentage inside (DT-01).
struct ScoreRing: View {
    let score: Int
    var size: CGFloat = 120
    var lineWidth: CGFloat = 12

    @Environment(\.locale) private var locale

    private var clamped: Int { min(max(score, 0), 100) }
    private var language: AppLanguage { AppLanguage(locale: locale) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(clamped) / 100)
                .stroke(ScoreLevel(score: clamped).color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(verbatim: Formatters.percent(clamped, language: language))
                .font(.system(size: size * 0.26, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .padding(lineWidth)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Risk score"))
        .accessibilityValue(Text(verbatim: Formatters.percent(clamped, language: language)))
    }
}

#Preview {
    HStack(spacing: 16) {
        ScoreRing(score: 41, size: 72, lineWidth: 8)
        ScoreRing(score: 63, size: 72, lineWidth: 8)
        ScoreRing(score: 92, size: 72, lineWidth: 8)
    }
    .padding()
}
