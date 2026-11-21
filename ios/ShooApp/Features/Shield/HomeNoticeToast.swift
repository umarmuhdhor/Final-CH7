import SwiftUI

/// Option A (plan/alief/proposal/pairing-feedback.md, Figma "Alief Revishit Flow" 2364:3633): the toast on Home after a
/// role or pairing change. Like an iOS notification banner (Alief, 20 Nov 2026): a solid white card 8 pt under the
/// status bar, 16 pt from the edges, over ⇆ and the avatar while it shows; compact, so the hero's shield stays clear.
/// One row: a 40 pt tile in the change's colour, the title with at most two lines under it, and a small "Undang" when
/// Home has an invite ready. Slides in from the top and leaves upwards (a fade with Reduce Motion); closes by itself,
/// with a tap, or swiped up; VoiceOver reads it once.
struct HomeNoticeToast: View {
    let notice: HomeNotice
    /// "Undang": only for "Mode Guardian aktif" while Home's invite code is ready.
    let onInvite: (() -> Void)?
    let onClose: () -> Void
    @Environment(\.locale) private var locale
    @Environment(\.shooReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var drag: CGFloat = 0

    /// Long enough to read; longer with a button to reach, and much longer while VoiceOver reads (WCAG 2.2.1).
    static func duration(hasAction: Bool, voiceOver: Bool) -> Duration {
        if voiceOver { return .seconds(10) }
        return hasAction ? .seconds(6) : .seconds(4)
    }

    private var language: AppLanguage { AppLanguage(locale: locale) }

    var body: some View {
        HStack(spacing: 10) {
            tile
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .onboardingFont(17, weight: .semibold, relativeTo: .headline)
                    .foregroundStyle(HomeTheme.ink)
                Text(verbatim: line)
                    .onboardingFont(14, relativeTo: .subheadline)
                    .foregroundStyle(HomeTheme.secondaryInk)
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
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 30)
                        .background(HomeTheme.action, in: Capsule())
                        // 44 pt to tap, though it looks smaller.
                        .contentShape(Rectangle().inset(by: -7))
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Opens the share sheet with your invite link"))
                .accessibilityIdentifier("home.notice.invite")
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 12)
        .padding(.vertical, 12)
        // Solid: over Home's cards, the text under it must not show through.
        .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 24, y: 8)
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
            // "Mode Guardian aktif" may get "Undang" a moment later (the code loads), so it always stays longer.
            let wait = Self.duration(hasAction: notice == .guardianOn, voiceOver: UIAccessibility.isVoiceOverRunning)
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled else { return }
            onClose()
        }
    }

    /// A mode change shows Home's own shield (`HalftoneShield`), teal for Guardian and blue for Pribadi, as on that
    /// Home's hero (Alief, 21 Nov 2026). Other changes keep the Figma tile: 40 pt, 11 pt corners, light-to-dark, a
    /// white glyph.
    @ViewBuilder private var tile: some View {
        if isModeChange {
            // The hero is 220 × 176 with the glass centred 18 pt left and 12.7 pt low; scaled to about 31 × 36 and
            // moved back to the middle of the 40 pt slot, then 4 pt left (Alief), so it does not crowd the title.
            let scale: CGFloat = 0.3
            HalftoneShield(tint: notice == .guardianOn ? .teal : .blue)
                .scaleEffect(scale)
                .offset(x: 18 * scale - 4, y: -12.7 * scale)
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)
        } else {
            plainTile
        }
    }

    private var isModeChange: Bool {
        switch notice {
        case .guardianOn, .personalOn: true
        default: false
        }
    }

    private var plainTile: some View {
        Image(systemName: isDisconnect ? "minus" : "checkmark")
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 40, height: 40)
            .background(
                LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
            .accessibilityHidden(true)
    }

    private var isDisconnect: Bool {
        if case .disconnected = notice { return true }
        return false
    }

    /// Teal for Guardian (the tip's gradient), green for a connection, blue for Pribadi (Home's hero), grey for a
    /// disconnect.
    private var colors: [Color] {
        switch notice {
        case .guardianOn: [Color(red: 0.42, green: 0.78, blue: 0.79), Color(red: 0.24, green: 0.60, blue: 0.64)]
        case .personalOn: [HomeTheme.heroLight, HomeTheme.heroDark]
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
        case .personalOn(let keepsFamily):
            keepsFamily
                ? L10n.string("Your protection stays on. Your family stays connected.", language: language)
                : L10n.string("Your protection stays on.", language: language)
        case .memberJoined(let name): L10n.string("You now help protect \(name).", language: language)
        case .connected(let guardian): L10n.string("\(guardian) will be told about dangerous sites.", language: language)
        case .disconnected: L10n.string("You no longer get their warnings.", language: language)
        }
    }
}

#Preview("Guardian on") {
    ZStack(alignment: .top) {
        Color.teal.ignoresSafeArea()
        HomeNoticeToast(notice: .guardianOn, onInvite: {}, onClose: {})
            .padding(.top, 8)
    }
}

#Preview("Member joined") {
    ZStack(alignment: .top) {
        Color.teal.ignoresSafeArea()
        HomeNoticeToast(notice: .memberJoined(name: "Ibu"), onInvite: nil, onClose: {})
            .padding(.top, 8)
    }
}
