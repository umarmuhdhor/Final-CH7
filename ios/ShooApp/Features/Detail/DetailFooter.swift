import SwiftUI
import UIKit

/// Figma "Footer" of Detail (416:9255 / 416:9362 / 480:5768): the guardian's question with Aman / Bahaya
/// (GD-07, warning and blocked alike), or the card saying who verified it. "Ubah" on either verdict
/// brings the buttons back; a new choice replaces the old one. No confirmation dialog.
struct DetailFooter: View {
    let verdict: Verdict?
    let viewerDeviceId: String?
    let canValidate: Bool
    /// Why the last verdict was not saved (BH-27); nil when it was, or none was sent.
    let failure: DetailModel.VerdictError?
    /// The person who opened the site, when it isn't the viewer (the note under a safe verdict).
    let ownerName: String?
    /// Blocked sites ask "Apakah situs ini berbahaya?", warnings "Apakah situs ini benar penipuan?".
    var isBlocked = false
    let onDecide: (Verdict.Value) -> Void

    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.shooReduceMotion) private var reduceMotion
    @State private var isChanging = false
    private var language: AppLanguage { AppLanguage(locale: locale) }

    static func message(_ failure: DetailModel.VerdictError) -> LocalizedStringKey {
        switch failure {
        case .connection: "Couldn't save. Check your connection and try again."
        case .notAllowed: "You're no longer this person's guardian, so you can't mark this site."
        case .tooMany: "Too many changes in a minute. Wait a moment, then try again."
        case .locked: "This site stays safe until Shoo's weekly review. You can change it after that."
        }
    }

    private var showsButtons: Bool { canValidate && (verdict == nil || isChanging) }
    private var lockedUntil: Date? { verdict.flatMap { VerdictLock.lockedUntil($0, now: Date()) } }

    /// The window's home indicator inset (34 on Face ID iPhones, 0 with a Home button). Read from the window,
    /// never from this footer's own geometry: that safe area moves while the tab bar hides, and feeding it
    /// back into the padding re-ran the layout inside `UITabBarController` forever (QA 2026-11-10 #1,
    /// 100 % CPU after a push tap).
    private static var homeIndicatorInset: CGFloat {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        return (windows.first(where: \.isKeyWindow) ?? windows.first)?.safeAreaInsets.bottom ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsButtons {
                Text(isBlocked ? "Is this site dangerous?" : "Is this site really a scam?")
                    // Figma "Pertanyaan": SF Pro Rounded 17, 140 %.
                    .activityFont(17, rounded: true)
                    .figmaLineHeight(23.8, relativeTo: .body)
                    .foregroundStyle(DetailStyle.secondary)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                buttons
            } else if let verdict {
                VerifiedCard(
                    verdict: verdict,
                    viewerDeviceId: viewerDeviceId,
                    // Either verdict can be changed (R4: Safe ⇄ NotSafe, an upsert), so a mis-tapped
                    // Danger can be undone and the buttons' "You can change it later" holds (QA 2026-11-11 #5).
                    // An "Aman" waits for the weekly AI review (VerdictLock); "Bahaya" can always change.
                    canChange: canValidate && lockedUntil == nil,
                    onChange: { isChanging = true }
                )
                if verdict.value == .safe, let ownerName {
                    // #369: "Aman" vouches for this link on both phones: no block, card or sheet while it stands.
                    Text("Shoo no longer blocks or warns \(ownerName) on this link.")
                        .activityFont(13, rounded: true)
                        .foregroundStyle(DetailStyle.secondary)
                        // Figma: centred, 140 % line height.
                        .lineSpacing(2.7)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 4)))
                }
                if canValidate, let lockedUntil {
                    let day = lockedUntil.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale))
                    Label("You can change this after Shoo's weekly review, \(day).", systemImage: "lock.fill")
                        .activityFont(13, rounded: true)
                        .foregroundStyle(DetailStyle.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("detail.verdictLocked")
                }
            }
            if let failure {
                Label(Self.message(failure), systemImage: "exclamationmark.triangle.fill")
                    .activityFont(13)
                    .foregroundStyle(DetailStyle.title)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("detail.verdictError")
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        // Figma: 34 pt from the screen's bottom edge, i.e. right on the home indicator area.
        .padding(.bottom, max(0, 34 - Self.homeIndicatorInset))
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                stops: [
                    .init(color: DetailStyle.footer.opacity(0), location: 0),
                    .init(color: DetailStyle.footer.opacity(0.96), location: 0.3),
                    .init(color: DetailStyle.footer, location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
        // A saved choice from the server closes "Ubah".
        .onChange(of: verdict) { _, _ in isChanging = false }
        // Safe / Danger saved: the buttons hand over to the verified card and its note with a short ease. Keyed
        // on the verdict only, never on this footer's geometry (GD-06).
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy(duration: 0.25), value: verdict?.value)
        // "Couldn't save" is felt too, not only read. Haptic only: the animation above stays keyed on the verdict.
        .sensoryFeedback(.error, trigger: failure != nil) { _, now in now }
    }

    /// Side by side; stacked at accessibility sizes so the words never wrap per letter.
    private var buttons: some View {
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            Button { onDecide(.safe) } label: {
                Label("Safe", systemImage: "checkmark.circle.fill")
            }
            .buttonStyle(VerdictButtonStyle(kind: .safe, selected: verdict?.value == .safe))
            .accessibilityAddTraits(verdict?.value == .safe ? .isSelected : [])
            .accessibilityIdentifier("detail.verdict.safe")
            Button { onDecide(.notSafe) } label: {
                Label("Danger", systemImage: "exclamationmark.circle.fill")
            }
            .buttonStyle(VerdictButtonStyle(kind: .notSafe, selected: verdict?.value == .notSafe))
            .accessibilityAddTraits(verdict?.value == .notSafe ? .isSelected : [])
            .accessibilityIdentifier("detail.verdict.notSafe")
        }
        .accessibilityHint(Text("Applies right away. You can change it later."))
    }
}

/// Aman: white capsule, dark text. Bahaya: red gradient with a darker rim, white text. 56 pt high.
private struct VerdictButtonStyle: ButtonStyle {
    let kind: Verdict.Value
    let selected: Bool

    @Environment(\.shooReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(VerdictLabelStyle())
            .activityFont(17, .semibold, tracking: -0.2125)
            .foregroundStyle(kind == .safe ? DetailStyle.title : .white)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background {
                if kind == .safe {
                    // Figma: #E3E3E3 spread 1 (a 1 pt ring outside the capsule) over the spread −3 drop shadow.
                    Capsule().fill(selected ? DetailStyle.title : DetailStyle.safeStroke)
                        .padding(selected ? -2 : -1)
                    Capsule().fill(.white).figmaButtonShadow()
                } else {
                    Capsule().fill(LinearGradient(colors: [DetailStyle.dangerTop, DetailStyle.dangerBottom], startPoint: .bottom, endPoint: .top))
                    Capsule().strokeBorder(DetailStyle.dangerTop, lineWidth: selected ? 3 : 1.5)
                }
            }
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

private struct VerdictLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        // Figma: 8 pt between icon and word.
        HStack(spacing: 8) {
            configuration.icon
            configuration.title.lineLimit(2)
        }
    }
}

/// Figma "Catatan": "Diverifikasi sebagai penipuan" / "Diverifikasi aman", "oleh Adhella · Baru saja".
private struct VerifiedCard: View {
    let verdict: Verdict
    let viewerDeviceId: String?
    let canChange: Bool
    let onChange: () -> Void

    @Environment(\.locale) private var locale
    private var language: AppLanguage { AppLanguage(locale: locale) }
    private var isScam: Bool { verdict.value == .notSafe }

    var body: some View {
        HStack(spacing: 12) {
            // Figma "Verified Note": the same check for both, red on pink or green on mint.
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(isScam ? DetailStyle.scamIcon : DetailStyle.safeIcon)
                .frame(width: 40, height: 40)
                .background(isScam ? DetailStyle.scamIconFill : DetailStyle.safeIconFill, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(isScam ? "Verified as a scam" : "Verified safe")
                    .activityFont(16, .medium, tracking: -0.16)
                    .foregroundStyle(DetailStyle.title)
                Text(verbatim: VerdictNote.byline(for: verdict, viewerDeviceId: viewerDeviceId, language: language))
                    .activityFont(13, rounded: true)
                    .foregroundStyle(DetailStyle.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("detail.verdictNote")
            if canChange {
                Button("Change", action: onChange)
                    .activityFont(15, .medium, tracking: -0.15)
                    .foregroundStyle(DetailStyle.change)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityHint(Text("Shows the Safe and Danger buttons again"))
                    .accessibilityIdentifier("detail.verdictChange")
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 16)
        .padding(.vertical, 14)
        .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.9)))
        .figmaCardShadow()
    }
}
