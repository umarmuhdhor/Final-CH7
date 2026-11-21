import SwiftUI

/// Option A (plan/alief/proposal/pairing-feedback.md): the toast on Home after a role or pairing change. Since fase 29g
/// it follows Figma "alief notif" section 2 (2431:12760, Alief chose B on 22 Nov 2026): a gradient card in the change's
/// colour with Shoo peeking over its left edge in a pose that fits, 16 pt from the edges and 8 pt under the status bar
/// (Shoo's head included), over ⇆ and the avatar while it shows. The title with at most two lines under it, and a small
/// "Undang" when Home has an invite ready. Slides in from the top and leaves upwards (a fade with Reduce Motion);
/// closes by itself, with a tap, or swiped up; VoiceOver reads it once.
struct HomeNoticeToast: View {
    let notice: HomeNotice
    /// "Undang": only for "Mode Guardian aktif" while Home's invite code is ready.
    let onInvite: (() -> Void)?
    let onClose: () -> Void
    @Environment(\.locale) private var locale
    @Environment(\.shooReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var drag: CGFloat = 0

    /// Figma (drawn at 2x): Shoo 86 pt tall, 8 pt in from the card's left edge, 22 pt over its top; the text starts at 96.
    private static let mascotHeight: CGFloat = 86
    private static let mascotOverhang: CGFloat = 22
    private static let textInset: CGFloat = 96

    /// Long enough to read; longer with a button to reach, and much longer while VoiceOver reads (WCAG 2.2.1).
    static func duration(hasAction: Bool, voiceOver: Bool) -> Duration {
        if voiceOver { return .seconds(10) }
        return hasAction ? .seconds(6) : .seconds(4)
    }

    private var language: AppLanguage { AppLanguage(locale: locale) }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .onboardingFont(16, weight: .semibold, relativeTo: .headline)
                    .foregroundStyle(.white)
                Text(verbatim: line)
                    .onboardingFont(13, relativeTo: .subheadline)
                    .foregroundStyle(.white.opacity(0.92))
                    // Two lines keep the banner short; larger text sizes may wrap further (VoiceOver reads it all).
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("home.notice.text")
            if let onInvite {
                Button(action: onInvite) {
                    Text("Invite")
                        .onboardingFont(14, weight: .semibold, relativeTo: .subheadline)
                        .foregroundStyle(style.ink)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 30)
                        .background(.white, in: Capsule())
                        // 44 pt to tap, though it looks smaller.
                        .contentShape(Rectangle().inset(by: -7))
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Opens the share sheet with your invite link"))
                .accessibilityIdentifier("home.notice.invite")
            }
        }
        .padding(.leading, Self.textInset)
        .padding(.trailing, 12)
        .padding(.vertical, 16)
        .frame(minHeight: 85)
        .background(
            LinearGradient(colors: style.colors, startPoint: .leading, endPoint: .trailing),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        // Figma: #0D1A33 at 18 %, blur 24, 8 down.
        .shadow(color: Color(hex: 0x0D1A33, opacity: 0.18), radius: 12, y: 8)
        // Shoo stands on the card's left part and peeks over its top edge.
        .overlay(alignment: .topLeading) {
            MascotImage(pose: style.pose, height: Self.mascotHeight)
                .offset(x: 8, y: -Self.mascotOverhang)
        }
        .padding(.top, Self.mascotOverhang)
        .environment(\.colorScheme, .light)
        .padding(.horizontal, 16)
        .offset(y: min(drag, 0))
        .contentShape(Rectangle())
        .onTapGesture(perform: onClose)
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { drag = $0.translation.height }
                .onEnded { value in
                    if value.translation.height < -24 { onClose() }
                    withAnimation(reduceMotion ? nil : .snappy) { drag = 0 }
                }
        )
        .accessibilityElement(children: .contain)
        .accessibilityAction(.escape, onClose)
        .accessibilityIdentifier("home.notice")
        .task {
            AccessibilityNotification.Announcement("\(title). \(line)").post()
            #if DEBUG
            // `-debug.homeNotice` screenshots: the toast stays until tapped.
            if MainTabView.screenshotNotice != nil { return }
            #endif
            // "Mode Guardian aktif" may get "Undang" a moment later (the code loads), so it always stays longer.
            let wait = Self.duration(hasAction: notice == .guardianOn, voiceOver: UIAccessibility.isVoiceOverRunning)
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled else { return }
            onClose()
        }
    }

    /// Figma "alief notif" section 2: the card's gradient (light on the left), Shoo's pose, and the "Undang" text colour.
    var style: (colors: [Color], pose: Mascot, ink: Color) {
        switch notice {
        case .guardianOn: ([Color(hex: 0x6BC7C9), Color(hex: 0x3D99A3)], .hero, Color(hex: 0x2B7A82))
        case .personalOn: ([Color(hex: 0x5AA9F5), Color(hex: 0x2F6FE0)], .idle, Color(hex: 0x2F6FE0))
        case .memberJoined: ([Color(hex: 0x70C29E), Color(hex: 0x21A06B)], .celebrate, Color(hex: 0x17784F))
        case .connected: ([Color(hex: 0x70C29E), Color(hex: 0x21A06B)], .wave, Color(hex: 0x17784F))
        case .disconnected: ([Color(hex: 0xA3A8B0), Color(hex: 0x737A87)], .sorry, Color(hex: 0x4F5562))
        }
    }

    var title: String {
        switch notice {
        case .guardianOn: L10n.string("Guardian mode on", language: language)
        case .personalOn: L10n.string("Personal mode on", language: language)
        case .memberJoined(let name): L10n.string("\(name) is connected", language: language)
        case .connected(let guardian): L10n.string("Connected with \(guardian)", language: language)
        case .disconnected(let name): L10n.string("\(name) is no longer connected", language: language)
        }
    }

    /// What the change means for the user, not what to tap: the button says that.
    var line: String {
        switch notice {
        case .guardianOn: L10n.string("You'll be told when your family opens a dangerous site.", language: language)
        case .personalOn: L10n.string("Your protection stays on.", language: language)
        case .memberJoined(let name): L10n.string("You now help protect \(name).", language: language)
        case .connected(let guardian): L10n.string("\(guardian) will be told about dangerous sites.", language: language)
        case .disconnected: L10n.string("You no longer get their warnings.", language: language)
        }
    }
}

#Preview("Guardian on") {
    ZStack(alignment: .top) {
        Color(.systemGroupedBackground).ignoresSafeArea()
        HomeNoticeToast(notice: .guardianOn, onInvite: {}, onClose: {})
            .padding(.top, 8)
    }
}

#Preview("Member joined") {
    ZStack(alignment: .top) {
        Color(.systemGroupedBackground).ignoresSafeArea()
        HomeNoticeToast(notice: .memberJoined(name: "Ibu"), onInvite: nil, onClose: {})
            .padding(.top, 8)
    }
}
