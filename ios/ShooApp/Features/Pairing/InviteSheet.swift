import SwiftUI
import UIKit

/// GD-04 in onboarding (Figma "Kirim Undangan"): QR, the 6-digit code, "Refresh code", and a row to
/// copy or send the invite. Same code rules as `FamilyCodeView` (valid 30 min, copy expires with it).
struct InviteSheet: View {
    /// The check mark: the Guardian is done inviting.
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL
    @Environment(\.shooReduceMotion) private var reduceMotion
    @State private var model: FamilyCodeModel
    /// Text for the system share sheet ("More", or WhatsApp / Messages when they can't open).
    @State private var shareText: ShareText?
    /// Bumped by each copy: "Link undangan tersalin" shows for a moment in place of "Refresh code".
    @State private var copies = 0
    @State private var showsCopiedNote = false

    init(repository: any ShooRepository, onDone: @escaping () -> Void) {
        _model = State(initialValue: FamilyCodeModel(repository: repository))
        self.onDone = onDone
    }

    private var language: AppLanguage { AppLanguage(locale: locale) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 15) {
                    Text("Scan the QR code or send the link")
                        .onboardingFont(27, weight: .medium, relativeTo: .title)
                        .tracking(-0.27)
                        .figmaLineHeight(29.7, glyphOffset: -2.7, relativeTo: .title)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(OnboardingTheme.ink)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.bottom, 9)
                    codeContent
                        // Figma: the QR card and code are 311 pt wide on a 402 pt screen.
                        .padding(.horizontal, 25)
                }
                .padding(.horizontal, 20)
                // Figma: the headline 32 pt under the toolbar.
                .padding(.top, 32)
                .frame(maxWidth: 400)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .safeAreaInset(edge: .bottom) {
                // Figma "App Icon Row": 18 above the icons; the names end 80 pt above the screen bottom.
                footer
                    .padding(.horizontal, 24)
                    .padding(.top, 18)
                    .padding(.bottom, 46)
                    .frame(maxWidth: .infinity)
                    .background(OnboardingTheme.background)
                    .animation(.easeInOut(duration: 0.25), value: stateKind)
            }
            .background(OnboardingTheme.background.ignoresSafeArea())
            .navigationTitle(localized: "Send invite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(Text("Close"))
                        .accessibilityIdentifier("invite.close")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: onDone) { Image(systemName: "checkmark") }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.circle)
                        .accessibilityLabel(Text("Done"))
                        .accessibilityIdentifier("invite.done")
                }
            }
            .task { await model.run() }
            .task(id: copies) {
                guard copies > 0 else { return }
                withAnimation(StateMotion.enter(reduceMotion: reduceMotion)) { showsCopiedNote = true }
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.25)) { showsCopiedNote = false }
            }
            .sensoryFeedback(.success, trigger: copies) { _, new in new > 0 }
            .sheet(item: $shareText) { item in
                InviteActivityView(text: item.text)
                    .presentationDetents([.medium, .large])
                    .ignoresSafeArea()
            }
        }
        .presentationDragIndicator(.visible)
        .environment(\.colorScheme, .light)
        .privacyCover()
    }

    @ViewBuilder
    private var codeContent: some View {
        switch model.codeState {
        case .loading:
            // Figma "Kirim Undangan · Mengambil kode" (1681:5872): the QR and code as grey blocks that shimmer.
            VStack(spacing: 15) {
                card { InviteQRSkeleton() }
                Capsule()
                    .fill(Color(hex: 0xE2E7EE))
                    .frame(width: 112, height: 14)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(OnboardingTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .shimmering()
            .accessibilityHidden(true)
            Text("Preparing the invite code…")
                .onboardingFont(17, design: .rounded, relativeTo: .body)
                .foregroundStyle(Color(hex: 0x6A717E))
                .padding(.top, 2)
                .accessibilityIdentifier("invite.loading")
        case .ready(let code):
            card {
                if let url = model.inviteURL, let qr = QRCode.image(for: url.absoluteString) {
                    Image(uiImage: qr)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        // Figma: the code's modules span 240 pt of the 311 × 303 card.
                        .padding(.horizontal, 25)
                        .padding(.vertical, 21)
                        .accessibilityLabel(Text("QR code to join your family"))
                        .accessibilityIdentifier("invite.qr")
                }
            }
            Text(verbatim: FamilyCodeModel.display(code.code))
                // Figma "SF Pro Text Bold 20", -2 %.
                .onboardingFont(20, weight: .bold, tracking: -0.4, family: .text, relativeTo: .title3)
                .monospacedDigit()
                // "Refresh code": the digits roll to the new code (a cross-fade with Reduce Motion). Only the code;
                // the "Valid for" countdown under it ticks every second and stays still.
                .contentTransition(reduceMotion ? .opacity : .numericText())
                .animation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy(duration: 0.3), value: code.code)
                .foregroundStyle(OnboardingTheme.ink)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(OnboardingTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityLabel(Text("Code \(code.code.map(String.init).joined(separator: " "))"))
                .accessibilityIdentifier("invite.code")
            ZStack {
                if showsCopiedNote {
                    // Figma "Link tersalin" (1681:6222): a check and the line where "Refresh code" was.
                    Label {
                        Text("Invite link copied")
                    } icon: {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                            .foregroundStyle(Color(hex: 0x34C759))
                    }
                    .onboardingFont(15, weight: .medium, family: .display, relativeTo: .subheadline)
                    .foregroundStyle(Color(hex: 0x191D2F))
                    .frame(minHeight: 44)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.92)))
                    .accessibilityIdentifier("invite.copiedNote")
                } else {
                    refreshAndCountdown
                        .transition(.opacity)
                }
            }
        case .unavailable:
            // Figma "Gagal mengambil kode" (1681:5974); "Try again" is the footer button.
            StateMessage(
                systemImage: "exclamationmark.arrow.circlepath",
                tint: Color(hex: 0xE5483B),
                title: "Code can't be made yet",
                message: "Check your internet connection, then try again."
            )
            .accessibilityIdentifier("invite.unavailable")
        case .full:
            // Figma "Keluarga penuh" (1681:6059); "Manage family" is the footer button.
            StateMessage(
                systemImage: "person.2.fill",
                symbolSize: 27,
                tint: Color(hex: 0x136CB7),
                title: "Family is full",
                message: "A family has at most 3 people.\nRemove one to invite again."
            )
            .accessibilityIdentifier("invite.full")
        }
    }

    @ViewBuilder
    private var refreshAndCountdown: some View {
        if case .ready = model.codeState {
            VStack(spacing: 2) {
                Button {
                    // A new code: the old one stops working, also in links already sent.
                    Task { await model.refreshCode(replace: true) }
                } label: {
                    if model.canReplace {
                        Label("Refresh code", systemImage: "arrow.clockwise")
                    } else {
                        // Waiting a minute after the last refresh (issue #227): the code on screen keeps working.
                        Label("New code in \(model.replaceUnlocksIn)", systemImage: "lock.fill")
                            .monospacedDigit()
                    }
                }
                // Figma "Refresh Kode": SF Pro Display Semibold 15, no tracking.
                .buttonStyle(OnboardingLinkButtonStyle(color: model.canReplace ? Self.refreshBlue : OnboardingTheme.secondaryInk, weight: .semibold, family: .display, tracking: 0))
                .disabled(!model.canReplace)
                .accessibilityIdentifier("invite.refresh")
                Text("Valid for \(model.timeLeft)")
                    .onboardingFont(13, design: .rounded, relativeTo: .footnote)
                    .monospacedDigit()
                    .foregroundStyle(OnboardingTheme.secondaryInk)
                    .accessibilityIdentifier("invite.countdown")
            }
        }
    }

    /// Which footer and body show; their swaps cross-fade.
    private var stateKind: Int {
        switch model.codeState {
        case .loading: 0
        case .ready: 1
        case .unavailable: 2
        case .full: 3
        }
    }

    @ViewBuilder
    private var footer: some View {
        switch model.codeState {
        case .loading:
            InviteShareRowSkeleton()
        case .ready:
            shareRow
        case .unavailable:
            Button("Try again") { Task { await model.refreshCode() } }
                .buttonStyle(OnboardingCapsuleButtonStyle())
                // Figma: the button ends 115 pt above the screen bottom, higher than the icon row.
                .padding(.bottom, 34)
                .accessibilityIdentifier("invite.retry")
        case .full:
            // Profile is right under this sheet: closing it shows the family to remove someone from.
            Button("Manage family") { dismiss() }
                .buttonStyle(OnboardingCapsuleButtonStyle())
                .padding(.bottom, 34)
                .accessibilityIdentifier("invite.manageFamily")
        }
    }

    /// White rounded square that holds the QR (Figma "Frame 87", 311 × 303, radius 28).
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity)
            .aspectRatio(311 / 303, contentMode: .fit)
            .background(.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            // The QR stays black on white in dark mode too (scanners need the contrast).
            .environment(\.colorScheme, .light)
    }

    private static let refreshBlue = Color(red: 0x03 / 255, green: 0x67 / 255, blue: 0xB6 / 255)
    /// WhatsApp's brand green, so the tile is recognised at a glance.
    private static let whatsAppGreen = Color(red: 0x25 / 255, green: 0xD3 / 255, blue: 0x66 / 255)

    private var shareRow: some View {
        let text = model.code.map { FamilyCodeModel.inviteText(for: $0, language: language) }
        return HStack(alignment: .top, spacing: 0) {
            ShareTile(title: model.copied ? "Copied" : "Copy", systemImage: model.copied ? "checkmark" : "doc.on.doc", style: .plain) {
                if model.copyInvite(language: language) {
                    copies += 1
                    AccessibilityNotification.Announcement(L10n.string("Invite link copied", language: language)).post()
                }
            }
            .accessibilityIdentifier("invite.copy")
            Spacer(minLength: 4)
            // WhatsApp first: that is where families send the link (PR-03), without a detour through "More".
            ShareTile(title: "WhatsApp", systemImage: "phone.bubble.fill", style: .filled(Self.whatsAppGreen)) {
                send(text, via: text.flatMap(InviteShare.whatsAppURL))
            }
            .accessibilityIdentifier("invite.whatsapp")
            Spacer(minLength: 4)
            ShareTile(title: "Messages", systemImage: "message.fill", style: .filled(.green)) {
                send(text, via: text.flatMap(InviteShare.messagesURL))
            }
            .accessibilityIdentifier("invite.messages")
            Spacer(minLength: 4)
            ShareTile(title: "More", systemImage: "square.and.arrow.up", style: .plain) {
                shareText = text.map(ShareText.init)
            }
            .accessibilityIdentifier("invite.more")
        }
        .disabled(text == nil || model.inviteURL == nil)
    }

    /// Opens WhatsApp / Messages with the invite filled in; the share sheet when that app can't open
    /// (WhatsApp not installed).
    private func send(_ text: String?, via url: URL?) {
        guard let text else { return }
        guard let url else {
            shareText = ShareText(text: text)
            return
        }
        openURL(url) { accepted in
            if !accepted { shareText = ShareText(text: text) }
        }
    }
}

/// `whatsapp:` and `sms:` links with the invite as the body. Nothing is sent until the user taps Send there.
enum InviteShare {
    /// RFC 3986 unreserved only: `&`, `=`, `+` and `?` in the text must not split the query.
    private static let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    static func messagesURL(body: String) -> URL? {
        body.addingPercentEncoding(withAllowedCharacters: allowed).flatMap { URL(string: "sms:&body=\($0)") }
    }

    /// WhatsApp's own scheme opens its contact picker with the text filled in. `open` needs no
    /// `LSApplicationQueriesSchemes` entry (only `canOpenURL` does); not installed → the share sheet.
    static func whatsAppURL(text: String) -> URL? {
        text.addingPercentEncoding(withAllowedCharacters: allowed).flatMap { URL(string: "whatsapp://send?text=\($0)") }
    }
}

private struct ShareText: Identifiable {
    let text: String
    var id: String { text }
}

/// One 66 pt round button with its name under it (Figma "App Icon Row").
private struct ShareTile: View {
    enum Style {
        case plain
        case filled(Color)
    }

    let title: LocalizedStringKey
    let systemImage: String
    let style: Style
    let action: () -> Void
    @Environment(\.shooReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                icon
                    .frame(width: 66, height: 66)
                // Figma "App Name": SF Pro Regular 11, the system share sheet's label.
                Text(title)
                    .onboardingFont(11, family: .sfPro, relativeTo: .caption2)
                    .foregroundStyle(OnboardingTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: 78)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var icon: some View {
        // Copy → checkmark: the symbol morphs (a cross-fade with Reduce Motion). The tile owns the image, so the
        // transition and its animation live here, keyed on the symbol name.
        let symbol = Image(systemName: systemImage).font(.system(size: 25))
            .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy(duration: 0.3), value: systemImage)
        switch style {
        case .plain:
            symbol
                .foregroundStyle(OnboardingTheme.ink)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.dynamic(0xEDEDED, dark: 0x2A303A), in: Circle())
        case .filled(let color):
            symbol
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
    }
}

/// Figma "Mengambil kode": the three finder squares and a centre block on #F5F8FC, all #E2E7EE / #EAEEF3.
private struct InviteQRSkeleton: View {
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height) * 0.84
            let block = side * 0.24
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: 0xF5F8FC))
                VStack {
                    HStack { finder(block, 0xE2E7EE); Spacer(); finder(block, 0xE2E7EE) }
                    Spacer()
                    HStack { finder(block, 0xE2E7EE); Spacer(); finder(block, 0xEAEEF3) }
                }
                .padding(side * 0.07)
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(hex: 0xEAEEF3))
                    .frame(width: block * 0.74, height: block * 0.74)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func finder(_ size: CGFloat, _ hex: UInt32) -> some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: hex)).frame(width: size, height: size)
    }
}

/// Figma "Skeleton bagikan": four grey tiles with a short bar under each, shimmering.
private struct InviteShareRowSkeleton: View {
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(0..<4, id: \.self) { index in
                if index > 0 { Spacer(minLength: 4) }
                VStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Color(hex: 0xE2E7EE)).frame(width: 66, height: 66)
                    Capsule().fill(Color(hex: 0xEAEEF3)).frame(width: 44, height: 8)
                }
                .frame(width: 78, height: 90, alignment: .top)
            }
        }
        .shimmering()
        .accessibilityHidden(true)
    }
}

/// System share sheet for the invite text.
private struct InviteActivityView: UIViewControllerRepresentable {
    let text: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [text], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        InviteSheet(repository: MockRepository(latency: .zero)) {}
    }
}
