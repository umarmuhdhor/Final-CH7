import SwiftUI
import UIKit

/// GD-04 in onboarding (Figma "Kirim Undangan"): QR, the 4-digit code, "Refresh code", and a row to
/// copy or send the invite. Same code rules as `FamilyCodeView` (new code every 60 s, copy expires).
struct InviteSheet: View {
    /// The check mark: the Guardian is done inviting.
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL
    @State private var model: FamilyCodeModel
    /// Text for the system share sheet ("More", or Messages / Mail when they can't open).
    @State private var shareText: ShareText?

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
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.black)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.bottom, 9)
                    codeContent
                        // Figma: the QR card and code are 311 pt wide on a 402 pt screen.
                        .padding(.horizontal, 25)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .frame(maxWidth: 400)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .safeAreaInset(edge: .bottom) {
                shareRow
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(OnboardingTheme.background)
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
            card {
                ProgressView().accessibilityLabel(Text("Getting a code"))
            }
        case .ready(let code):
            card {
                if let url = model.inviteURL, let qr = QRCode.image(for: url.absoluteString) {
                    Image(uiImage: qr)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .padding(28)
                        .accessibilityLabel(Text("QR code to join your family"))
                        .accessibilityIdentifier("invite.qr")
                }
            }
            Text(verbatim: code.code.map(String.init).joined(separator: " "))
                .onboardingFont(20, weight: .bold, relativeTo: .title3)
                .tracking(-0.4)
                .monospacedDigit()
                .foregroundStyle(OnboardingTheme.ink)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityLabel(Text("Code \(code.code.map(String.init).joined(separator: " "))"))
                .accessibilityIdentifier("invite.code")
            VStack(spacing: 2) {
                Button {
                    Task { await model.refreshCode() }
                } label: {
                    Label("Refresh code", systemImage: "arrow.clockwise")
                }
                .buttonStyle(OnboardingLinkButtonStyle(color: Self.refreshBlue, weight: .semibold))
                .accessibilityIdentifier("invite.refresh")
                Text("New code in \(model.secondsLeft) s")
                    .onboardingFont(13, design: .rounded, relativeTo: .footnote)
                    .monospacedDigit()
                    .foregroundStyle(OnboardingTheme.secondaryInk)
                    .accessibilityIdentifier("invite.countdown")
            }
        case .unavailable:
            card {
                VStack(spacing: 12) {
                    Text("Couldn't get a code").onboardingFont(17, weight: .semibold, relativeTo: .headline)
                    Button("Try again") { Task { await model.refreshCode() } }
                        .buttonStyle(OnboardingLinkButtonStyle())
                        .accessibilityIdentifier("invite.retry")
                }
                .padding(24)
            }
        case .full:
            card {
                Text("Your family is full (3 people). Remove someone to invite another person.")
                    .onboardingBodyStyle()
                    .padding(24)
            }
        }
    }

    /// White rounded square that holds the QR (Figma "Frame 87", 311 × 303, radius 28).
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity)
            .aspectRatio(311 / 303, contentMode: .fit)
            .background(.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private static let refreshBlue = Color(red: 0x03 / 255, green: 0x67 / 255, blue: 0xB6 / 255)

    private var shareRow: some View {
        let text = model.code.map { FamilyCodeModel.inviteText(for: $0, language: language) }
        return HStack(alignment: .top, spacing: 0) {
            ShareTile(title: "Copy", systemImage: model.copied ? "checkmark" : "doc.on.doc", style: .plain) {
                if model.copyInvite(language: language) {
                    AccessibilityNotification.Announcement(L10n.string("Invite link copied", language: language)).post()
                }
            }
            .accessibilityIdentifier("invite.copy")
            Spacer(minLength: 4)
            ShareTile(title: "Messages", systemImage: "message.fill", style: .filled(.green)) {
                send(text, via: text.flatMap(InviteShare.messagesURL))
            }
            .accessibilityIdentifier("invite.messages")
            Spacer(minLength: 4)
            ShareTile(title: "Mail", systemImage: "envelope.fill", style: .filled(.blue)) {
                send(text, via: text.flatMap { InviteShare.mailURL(subject: L10n.string("Join my family on Shoo", language: language), body: $0) })
            }
            .accessibilityIdentifier("invite.mail")
            Spacer(minLength: 4)
            ShareTile(title: "More", systemImage: "square.and.arrow.up", style: .plain) {
                shareText = text.map(ShareText.init)
            }
            .accessibilityIdentifier("invite.more")
        }
        .disabled(text == nil || model.inviteURL == nil)
    }

    /// Opens Messages / Mail with the invite filled in; the share sheet when that app can't open (e.g. no Mail account).
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

/// `sms:` and `mailto:` links with the invite as the body. Nothing is sent until the user taps Send there.
enum InviteShare {
    /// RFC 3986 unreserved only: `&`, `=`, `+` and `?` in the text must not split the query.
    private static let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    static func messagesURL(body: String) -> URL? {
        body.addingPercentEncoding(withAllowedCharacters: allowed).flatMap { URL(string: "sms:&body=\($0)") }
    }

    static func mailURL(subject: String, body: String) -> URL? {
        guard
            let subject = subject.addingPercentEncoding(withAllowedCharacters: allowed),
            let body = body.addingPercentEncoding(withAllowedCharacters: allowed)
        else { return nil }
        return URL(string: "mailto:?subject=\(subject)&body=\(body)")
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

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                icon
                    .frame(width: 66, height: 66)
                Text(title)
                    .onboardingFont(11, relativeTo: .caption2)
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
        let symbol = Image(systemName: systemImage).font(.system(size: 25))
        switch style {
        case .plain:
            symbol
                .foregroundStyle(OnboardingTheme.ink)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(red: 0xED / 255, green: 0xED / 255, blue: 0xED / 255), in: Circle())
        case .filled(let color):
            symbol
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
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
