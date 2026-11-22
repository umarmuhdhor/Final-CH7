import SwiftUI

/// Goldfish V3, option A (fase 29f): a "Scam terbaru" card opens how that scam works. `GET /scams/latest` only
/// sends the category, its label and a time (contracts/api.md), so the example lives here, one per category of
/// `admin.categories`; a category the app doesn't know yet gets the general one.
struct ScamModus: Equatable {
    /// The message that brings the link (SMS or chat).
    let message: LocalizedStringKey
    /// A made-up address on `.site`, never a real brand.
    let link: String
    /// The fake page's heading and the one thing it asks for.
    let pageTitle: LocalizedStringKey
    let field: LocalizedStringKey
    /// What happens to whoever fills it in.
    let explanation: LocalizedStringKey

    static func forCategory(_ category: String) -> ScamModus {
        switch category {
        case "phishing_bank":
            ScamModus(
                message: "BANK: Your account is blocked for now. Open this link to unlock it:",
                link: "bank-verifikasi.site", pageTitle: "Verify your account", field: "m-banking PIN",
                explanation: "The site copies a bank. The PIN you type is used at once to empty your account."
            )
        case "phishing_ewallet":
            ScamModus(
                message: "Your e-wallet balance expires today. Claim it now:",
                link: "dompet-klaim.site", pageTitle: "Claim your balance", field: "OTP code",
                explanation: "The OTP code lets them sign in to your e-wallet and move the money out."
            )
        case "marketplace_palsu":
            ScamModus(
                message: "Your parcel is on hold. Pay the extra shipping of Rp9,000 here:",
                link: "cek-paket-toko.site", pageTitle: "Pay for shipping", field: "Card number",
                explanation: "The shop is fake. The money or card details you send never come back."
            )
        case "undian_palsu":
            ScamModus(
                message: "Congratulations! You won Rp10,000,000. Claim your prize:",
                link: "hadiah-undian.site", pageTitle: "Claim your prize", field: "m-banking PIN",
                explanation: "There is no prize. You're asked for an \"admin fee\" or your bank details first."
            )
        case "investasi_bodong":
            ScamModus(
                message: "Triple your money in a month, guaranteed. Sign up here:",
                link: "profit-cepat.site", pageTitle: "Start investing", field: "First deposit",
                explanation: "The big profit doesn't exist. The money you put in can't be taken out again."
            )
        case "judi":
            ScamModus(
                message: "Double bonus on your first deposit. Play now:",
                link: "slot-bonus.site", pageTitle: "Deposit", field: "Deposit amount",
                explanation: "Online gambling is illegal in Indonesia. The money you put in is almost always lost."
            )
        case "pinjol_ilegal":
            ScamModus(
                message: "Loan paid out in 5 minutes, no collateral. Apply here:",
                link: "dana-kilat.site", pageTitle: "Apply for a loan", field: "ID card number",
                explanation: "Illegal lenders take your data and contacts, then collect with threats."
            )
        default:
            ScamModus(
                message: "Something on your account needs checking. Open this link:",
                link: "cek-akun.site", pageTitle: "Sign in", field: "Password",
                explanation: "The site copies a service you know to steal what you type."
            )
        }
    }
}

/// The sheet: the case's own label, then the example in two steps (Alief's pick for V3: a fake SMS link, then the
/// fake site asking for a PIN), what it costs, and three ways to stay safe. Presented with `peekSheet` (fase 29g):
/// Shoo peeks over the top edge; the page scrolls, so the grabber strip is where a drag closes it.
struct ScamModusSheet: View {
    let scamCase: ScamCase

    @Environment(\.closePeekSheet) private var close
    @Environment(\.locale) private var locale

    private var modus: ScamModus { .forCategory(scamCase.id) }

    var body: some View {
        ScrollView {
            content
        }
        .scrollBounceBehavior(.basedOnSize)
        // On the page only: set after the inset it would rename "Mengerti" too.
        .accessibilityIdentifier("scamModus.sheet")
        // Taller than most screens: the page scrolls, "Mengerti" stays in reach.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button("Got it") { close() }
                .buttonStyle(OnboardingCapsuleButtonStyle())
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .background(.white)
                .accessibilityIdentifier("scamModus.done")
        }
        // The grabber the system sheet drew. Its strip is a handle: the page under it scrolls, the strip moves the sheet.
        .overlay(alignment: .top) {
            Capsule().fill(ProfileStyle.sheetGrabber).frame(width: 36, height: 5)
                .padding(.top, 8)
                .frame(maxWidth: .infinity, minHeight: 24, alignment: .top)
                .background(.white.opacity(0.001), in: UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32))
                .accessibilityHidden(true)
        }
        .environment(\.colorScheme, .light)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            step(1, "A message arrives") { messageBubble }
            step(2, "The link opens a fake site") { fakeSite }
            Text(modus.explanation)
                .onboardingFont(16, design: .rounded, tracking: -0.31, relativeTo: .callout)
                .foregroundStyle(HomeTheme.bodyInk)
                .fixedSize(horizontal: false, vertical: true)
            tips
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 16)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("How this scam works")
                    .onboardingFont(15, weight: .semibold, design: .rounded, relativeTo: .subheadline)
                    .foregroundStyle(HomeTheme.dangerText)
                Text(verbatim: scamCase.title.text(for: AppLanguage(locale: locale).code))
                    .onboardingFont(28, weight: .semibold, relativeTo: .title)
                    .foregroundStyle(HomeTheme.navy)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { close() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(HomeTheme.secondaryInk)
                    .frame(width: 30, height: 30)
                    .background(HomeTheme.quietFill, in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .padding(.top, -7)
            .padding(.trailing, -7)
            .accessibilityLabel(Text("Close"))
            .accessibilityIdentifier("scamModus.close")
        }
    }

    private func step(_ number: Int, _ title: LocalizedStringKey, @ViewBuilder visual: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(verbatim: "\(number)")
                    .onboardingFont(13, weight: .bold, design: .rounded, relativeTo: .footnote)
                    .foregroundStyle(.white)
                    .frame(minWidth: 22, minHeight: 22)
                    .background(HomeTheme.navy, in: Circle())
                    .accessibilityHidden(true)
                Text(title)
                    .onboardingFont(17, weight: .semibold, design: .rounded, relativeTo: .headline)
                    .foregroundStyle(HomeTheme.navy)
            }
            visual()
        }
    }

    /// An incoming SMS: grey bubble, the sender above it, the link blue and underlined as Messages shows it.
    private var messageBubble: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Unknown number")
                .onboardingFont(12, design: .rounded, relativeTo: .caption)
                .foregroundStyle(HomeTheme.secondaryInk)
                .padding(.leading, 12)
            (Text(modus.message) + Text(verbatim: " ") + Text(verbatim: modus.link).foregroundColor(HomeTheme.action).underline())
                .onboardingFont(16, relativeTo: .callout)
                .foregroundStyle(HomeTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(hex: 0xE9E9EB), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.trailing, 48)
        }
        .accessibilityElement(children: .combine)
    }

    /// A small browser: the address with a "Palsu" tag, the page's heading, the field it wants filled, a button.
    private var fakeSite: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(HomeTheme.secondaryInk)
                    .accessibilityHidden(true)
                Text(verbatim: modus.link)
                    .onboardingFont(14, relativeTo: .footnote)
                    .foregroundStyle(HomeTheme.ink)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Fake")
                    .onboardingFont(12, weight: .semibold, design: .rounded, relativeTo: .caption)
                    .foregroundStyle(HomeTheme.dangerText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(HomeTheme.dangerFill, in: Capsule())
                    .overlay(Capsule().strokeBorder(HomeTheme.dangerStroke, lineWidth: 0.75))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(HomeTheme.tileIconBackground)

            VStack(alignment: .leading, spacing: 10) {
                Text(modus.pageTitle)
                    .onboardingFont(18, weight: .semibold, relativeTo: .headline)
                    .foregroundStyle(HomeTheme.navy)
                Text(modus.field)
                    .onboardingFont(13, relativeTo: .footnote)
                    .foregroundStyle(HomeTheme.secondaryInk)
                Text(verbatim: "• • • • • •")
                    .onboardingFont(17, relativeTo: .body)
                    .foregroundStyle(HomeTheme.ink)
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                    .padding(.horizontal, 12)
                    .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(HomeTheme.rowStroke, lineWidth: 1))
                    .accessibilityHidden(true)
                Text("Continue")
                    .onboardingFont(15, weight: .semibold, relativeTo: .subheadline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(HomeTheme.dangerText.opacity(0.85), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)
            }
            .padding(14)
        }
        .background(Color(hex: 0xFAFBFC))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(HomeTheme.rowStroke, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var tips: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How to stay safe")
                .onboardingFont(17, weight: .semibold, design: .rounded, relativeTo: .headline)
                .foregroundStyle(HomeTheme.navy)
                .accessibilityAddTraits(.isHeader)
            tip("Don't open links in messages you weren't expecting.")
            tip("Never type a PIN, OTP or password on a site you reached from a link.")
            tip("Shoo warns you or blocks sites like this when you open them.")
        }
    }

    private func tip(_ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(HomeTheme.action)
                .accessibilityHidden(true)
            Text(text)
                .onboardingFont(16, design: .rounded, tracking: -0.31, relativeTo: .callout)
                .foregroundStyle(HomeTheme.bodyInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    Color.gray.sheet(isPresented: .constant(true)) {
        ScamModusSheet(scamCase: MockScenarios.scamCases(now: .now)[0])
    }
}
