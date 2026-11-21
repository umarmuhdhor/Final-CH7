import SwiftUI

/// Option A (plan/alief/proposal/pairing-feedback.md): the toast on Home after a role or pairing change. Since fase 29g
/// it is a `ShooToast` (Figma "alief notif" section 2, 2431:12760; Alief chose B on 22 Nov 2026): a gradient card in the
/// change's colour with Shoo in a pose that fits, over ⇆ and the avatar while it shows, and a small "Undang" when Home
/// has an invite ready.
struct HomeNoticeToast: View {
    let notice: HomeNotice
    /// "Undang": only for "Mode Guardian aktif" while Home's invite code is ready.
    let onInvite: (() -> Void)?
    let onClose: () -> Void
    @Environment(\.locale) private var locale

    /// Long enough to read; longer with a button to reach, and much longer while VoiceOver reads (WCAG 2.2.1).
    static func duration(hasAction: Bool, voiceOver: Bool) -> Duration {
        if voiceOver { return .seconds(10) }
        return hasAction ? .seconds(6) : .seconds(4)
    }

    private var language: AppLanguage { AppLanguage(locale: locale) }

    var body: some View {
        ShooToast(
            title: title, line: line, colors: style.colors, pose: style.pose, identifier: "home.notice",
            // "Mode Guardian aktif" may get "Undang" a moment later (the code loads), so it always stays longer.
            duration: Self.duration(hasAction: notice == .guardianOn, voiceOver: UIAccessibility.isVoiceOverRunning),
            staysOpen: staysOpenForScreenshots,
            onClose: onClose
        ) {
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
    }

    /// `-debug.homeNotice` screenshots: the toast stays until tapped.
    private var staysOpenForScreenshots: Bool {
        #if DEBUG
        MainTabView.screenshotNotice != nil
        #else
        false
        #endif
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
