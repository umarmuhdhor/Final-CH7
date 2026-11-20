import SwiftUI

/// Option A (plan/alief/proposal/pairing-feedback.md, Figma "Alief Revishit Flow" 2364:3633): the toast on Home after a
/// role or pairing change. A white card 12 pt above the tab bar, as wide as Home's cards (24 pt from the edges), so it
/// never covers the hero (Alief, 20 Nov 2026); one row: a 44 pt tile in the change's colour, the title with one line
/// under it, and "Undang" when Home has an invite ready. Closes by itself, with a tap, or swiped down; VoiceOver reads
/// it once.
struct HomeNoticeToast: View {
    let notice: HomeNotice
    /// "Undang": only for "Mode Guardian aktif" while Home's invite code is ready.
    let onInvite: (() -> Void)?
    let onClose: () -> Void
    @Environment(\.locale) private var locale
    @Environment(\.shooReduceMotion) private var reduceMotion
    @State private var drag: CGFloat = 0

    /// Long enough to read; longer with a button to reach, and much longer while VoiceOver reads (WCAG 2.2.1).
    static func duration(hasAction: Bool, voiceOver: Bool) -> Duration {
        if voiceOver { return .seconds(10) }
        return hasAction ? .seconds(6) : .seconds(4)
    }

    private var language: AppLanguage { AppLanguage(locale: locale) }

    var body: some View {
        HStack(spacing: 12) {
            tile
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .onboardingFont(17, weight: .semibold, relativeTo: .headline)
                    .foregroundStyle(HomeTheme.ink)
                Text(verbatim: line)
                    .onboardingFont(14, relativeTo: .subheadline)
                    .foregroundStyle(HomeTheme.secondaryInk)
                    .lineLimit(3)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("home.notice.text")
            if let onInvite {
                Button(action: onInvite) {
                    Text("Invite")
                        .onboardingFont(15, weight: .semibold, relativeTo: .subheadline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 34)
                        .background(HomeTheme.action, in: Capsule())
                        .contentShape(Rectangle().inset(by: -5))
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Opens the share sheet with your invite link"))
                .accessibilityIdentifier("home.notice.invite")
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 14)
        .padding(.vertical, 14)
        // Solid: over Home's cards, the text under it must not show through.
        .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 24, y: 8)
        .environment(\.colorScheme, .light)
        .padding(.horizontal, 24)
        .offset(y: max(drag, 0))
        .contentShape(Rectangle())
        .onTapGesture(perform: onClose)
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { drag = $0.translation.height }
                .onEnded { value in
                    if value.translation.height > 24 { onClose() }
                    withAnimation(reduceMotion ? nil : .snappy) { drag = 0 }
                }
        )
        .accessibilityElement(children: .contain)
        .accessibilityAction(.escape, onClose)
        .accessibilityIdentifier("home.notice")
        .task {
            AccessibilityNotification.Announcement("\(title). \(line)").post()
            // "Mode Guardian aktif" may get "Undang" a moment later (the code loads), so it always stays longer.
            let wait = Self.duration(hasAction: notice == .guardianOn, voiceOver: UIAccessibility.isVoiceOverRunning)
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled else { return }
            onClose()
        }
    }

    /// Figma: a 44 pt tile, 12 pt corners, light-to-dark in the change's colour (the ⇆ tip's tile), a white glyph.
    private var tile: some View {
        Image(systemName: isDisconnect ? "minus" : "checkmark")
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(
                LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .accessibilityHidden(true)
    }

    private var isDisconnect: Bool {
        if case .disconnected = notice { return true }
        return false
    }

    /// Teal for Guardian (the tip's gradient), green for a connection, navy for Pribadi, grey for a disconnect.
    private var colors: [Color] {
        switch notice {
        case .guardianOn: [Color(red: 0.42, green: 0.78, blue: 0.79), Color(red: 0.24, green: 0.60, blue: 0.64)]
        case .personalOn: [Color(red: 0.43, green: 0.49, blue: 0.62), Color(red: 0.12, green: 0.22, blue: 0.42)]
        case .memberJoined, .connected: [Color(red: 0.44, green: 0.76, blue: 0.62), Color(red: 0.13, green: 0.63, blue: 0.42)]
        case .disconnected: [Color(red: 0.64, green: 0.66, blue: 0.69), Color(red: 0.45, green: 0.48, blue: 0.53)]
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
    ZStack(alignment: .bottom) {
        Color.teal.ignoresSafeArea()
        HomeNoticeToast(notice: .guardianOn, onInvite: {}, onClose: {})
            .padding(.bottom, 12)
    }
}

#Preview("Member joined") {
    ZStack(alignment: .bottom) {
        Color.teal.ignoresSafeArea()
        HomeNoticeToast(notice: .memberJoined(name: "Ibu"), onInvite: nil, onClose: {})
            .padding(.bottom, 12)
    }
}
