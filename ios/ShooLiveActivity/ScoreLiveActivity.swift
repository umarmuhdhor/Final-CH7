import ActivityKit
import SwiftUI
import WidgetKit

/// EX-03: running score only. Driven by Live Activity push from the backend (path C, #49):
/// contracts/api.md "Live score (Dynamic Island)". The island exists only while a page is on screen
/// in Safari; the backend ends it (`event: end`) when the page leaves the screen.
/// Compact island follows Figma "Safari / Warning Sedang / Minimized" (node 882:2533): Shoo logo on the
/// left, a 20 pt mini ring on the right (track white 20 %, progress = score, 4 pt thick, from the top).
/// Expanded, minimal and lock screen have no Figma frame yet: built from the same two pieces.
struct ScoreLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ScoreActivityAttributes.self) { context in
            LockScreenView(state: context.state)
                .activityBackgroundTint(.black)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ShooLogo(size: 36)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    MiniRing(state: state, size: 36, showsScore: true)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(state.statusText)
                            .font(.headline)
                            .foregroundStyle(state.tone.color)
                        Text(state.domain)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                }
            } compactLeading: {
                ShooLogo(size: 24)
            } compactTrailing: {
                MiniRing(state: state, size: 20)
            } minimal: {
                MiniRing(state: state, size: 20)
            }
            .keylineTint(state.tone.color)
        }
    }
}

/// Shoo logo, exported from Figma ("final", 24 × 24, round).
private struct ShooLogo: View {
    let size: CGFloat

    var body: some View {
        Image("ShooLogo")
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .clipShape(Circle())
    }
}

/// Figma "Mini ring": Track (white 20 %) + Progress (tone colour), inner radius 0.6 → ring = 20 % of size.
private struct MiniRing: View {
    let state: ScoreActivityAttributes.ContentState
    let size: CGFloat
    var showsScore = false

    var body: some View {
        let lineWidth = size * 0.2
        ZStack {
            Circle()
                .stroke(.white.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(state.score, 0), 100)) / 100)
                .stroke(state.tone.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                .rotationEffect(.degrees(-90))
            if showsScore {
                Text("\(state.score)")
                    .font(.system(size: size * 0.33, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .contentTransition(.numericText(value: Double(state.score)))
            }
        }
        .padding(lineWidth / 2)
        .frame(width: size, height: size)
        .opacity(state.isAnalyzing ? 0.6 : 1)
        .accessibilityElement()
        .accessibilityLabel("Shoo \(state.score)%")
    }
}

private struct LockScreenView: View {
    let state: ScoreActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            ShooLogo(size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(state.statusText)
                    .font(.headline)
                    .foregroundStyle(state.tone.color)
                Text(state.domain)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
            Spacer()
            MiniRing(state: state, size: 40, showsScore: true)
        }
        .padding()
    }
}

private extension ScoreActivityAttributes.ContentState {
    var statusText: String {
        if isAnalyzing { return "Menganalisis…" }
        switch tone {
        case .safe: return "Aman"
        case .warning: return "Hati-hati"
        case .danger: return "Risiko tinggi"
        case .blocked: return "Diblokir"
        }
    }
}

private extension ScoreActivityAttributes.Tone {
    /// Warning = Figma #FFCC00. The others: iOS system colours in the same family (green, orange, red),
    /// like the extension's gauge.
    var color: Color {
        switch self {
        case .safe: return Color(red: 0x34 / 255, green: 0xC7 / 255, blue: 0x59 / 255)
        case .warning: return Color(red: 1, green: 0xCC / 255, blue: 0)
        case .danger: return Color(red: 1, green: 0x95 / 255, blue: 0)
        case .blocked: return Color(red: 1, green: 0x3B / 255, blue: 0x30 / 255)
        }
    }
}
