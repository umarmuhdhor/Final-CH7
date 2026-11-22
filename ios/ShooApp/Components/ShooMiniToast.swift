import SwiftUI

/// Figma "alief notif" section 8, "Toast kecil" (2447:13955, drawn at 2x; fase 29g): a one-word confirmation for
/// 1.5 s, a small gradient card with Shoo peeking over its left edge. No tap, no text beyond the word: the caller's
/// control already says what happened, and VoiceOver hears the caller's own announcement.
struct ShooMiniToast: View {
    enum Kind {
        /// "Tersalin": the invite code's Copy.
        case copied
    }

    let kind: Kind

    /// How long it stays.
    static let seconds: Double = 1.5

    // Figma: 52 tall, r 22; Shoo 62 tall, 12 pt in, 17 pt over the top; the word 75 pt from the left, 20 from the right.
    private static let height: CGFloat = 52
    private static let poseHeight: CGFloat = 62
    private static let overhang: CGFloat = 17

    private var title: LocalizedStringKey {
        switch kind {
        case .copied: "Copied"
        }
    }

    private var pose: Mascot {
        switch kind {
        case .copied: .thumbsUp
        }
    }

    /// Light on the left, dark on the right.
    private var colors: [Color] {
        switch kind {
        case .copied: [Color(hex: 0x7DD3B0), Color(hex: 0x2E9E6E)]
        }
    }

    var body: some View {
        Text(title)
            .onboardingFont(16, weight: .semibold, relativeTo: .headline)
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.leading, 75)
            .padding(.trailing, 20)
            .frame(minHeight: Self.height)
            .background(
                LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .overlay(alignment: .topLeading) {
                MascotImage(pose: pose, height: Self.poseHeight)
                    .offset(x: 12, y: -Self.overhang)
                    .accessibilityHidden(true)
            }
            .shadow(color: Color(hex: 0x0D1A33, opacity: 0.18), radius: 12, y: 8)
            .padding(.top, Self.overhang)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("miniToast")
    }
}

extension View {
    /// Shows `kind` at the top for 1.5 s each time `trigger` goes up (0 shows nothing).
    func shooMiniToast(_ kind: ShooMiniToast.Kind, trigger: Int) -> some View {
        modifier(ShooMiniToastModifier(kind: kind, trigger: trigger))
    }
}

private struct ShooMiniToastModifier: ViewModifier {
    let kind: ShooMiniToast.Kind
    let trigger: Int
    @State private var isShown = false
    @Environment(\.shooReduceMotion) private var reduceMotion
    @Environment(\.shooMiniToastSeconds) private var seconds

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if isShown {
                    ShooMiniToast(kind: kind)
                        .padding(.top, 8)
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                        .allowsHitTesting(false)
                }
            }
            .task(id: trigger) {
                guard trigger > 0 else { return }
                withAnimation(StateMotion.enter(reduceMotion: reduceMotion)) { isShown = true }
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.25)) { isShown = false }
            }
    }
}

private struct MiniToastSecondsKey: EnvironmentKey {
    static let defaultValue = ShooMiniToast.seconds
}

extension EnvironmentValues {
    /// How long a mini toast stays: 1.5 s, longer only in UI tests (`-UITestMiniToastSeconds`).
    var shooMiniToastSeconds: Double {
        get { self[MiniToastSecondsKey.self] }
        set { self[MiniToastSecondsKey.self] = newValue }
    }
}

#Preview("Tersalin") {
    ShooMiniToast(kind: .copied)
        .padding(40)
}
