import AVFoundation
import SwiftUI

/// Figma "Jadikan Safari Default". Shoo only runs in Safari, but no API says which browser is the default,
/// so this asks instead of checking. Settings paths per iOS version are BELUM DIVERIFIKASI on device.
enum SafariDefaultSetup {
    enum Step: Equatable, CaseIterable {
        case tapOpen
        case tapBrowserApp
        case openDefaultApps
        case openAppsSafari
        case openSafariLegacy
        case comeBack
    }

    static func steps(for version: OperatingSystemVersion) -> [Step] {
        let pick: Step
        switch (version.majorVersion, version.minorVersion) {
        case (18, 3...), (19..., _): pick = .tapBrowserApp
        case (18, 2): pick = .openDefaultApps
        case (18, _): pick = .openAppsSafari
        default: pick = .openSafariLegacy
        }
        return [.tapOpen, pick, .comeBack]
    }

    /// iOS 18.3+ opens the Default Apps page; before that only Shoo's own page in Settings exists.
    @MainActor
    static func openSettings() async {
        let address: String
        if #available(iOS 18.3, *) {
            address = UIApplication.openDefaultApplicationsSettingsURLString
        } else {
            address = UIApplication.openSettingsURLString
        }
        if let url = URL(string: address) {
            await UIApplication.shared.open(url)
        }
    }
}

extension SafariDefaultSetup.Step {
    var text: LocalizedStringKey {
        switch self {
        case .tapOpen: "Tap the button below to open Settings."
        case .tapBrowserApp: "Tap Browser App, then choose Safari."
        case .openDefaultApps: "Go to Apps › Default Apps › Browser App, then choose Safari."
        case .openAppsSafari: "Go to Apps › Safari › Default Browser App, then choose Safari."
        case .openSafariLegacy: "Go to Safari › Default Browser App, then choose Safari."
        case .comeBack: "Go back to Shoo, then tap Check & continue."
        }
    }
}

/// "Cek & lanjutkan" (Figma 2497:4919). No API reads the default browser, and none reads Safari's "All Websites"
/// setting for Shoo. An https link opened from the app goes to the DEFAULT browser, so one trip answers both: a
/// heartbeat from the extension that is newer than the tap means Safari is the default and Shoo runs there, and
/// it says whether Shoo may read every site (`extension.allSites`). With "Ask" and no answer to Safari's prompt the
/// extension never runs, so nothing arrives (simulator test 22 Nov 2026): that is `notSeen` too.
enum SafariCheck {
    enum Result: Equatable {
        /// Fresh heartbeat with every site allowed: on to the success screen.
        case passed
        /// Fresh heartbeat, but Safari lets Shoo read only some sites (F3 toast B).
        case someSitesOnly
        /// No heartbeat since the tap: another browser is the default, or Safari still asks.
        case notSeen
    }

    /// A heartbeat can land a moment after the user is back (same as ON-04, #135).
    static let recheck = (times: 10, every: Duration.seconds(2))

    /// The page the check opens (backend `GET /safari-check`), in the app's language. On the website `shoo.ai.id`,
    /// which passes this path through to the API: that host has no Universal Links, so iOS always opens it in the
    /// browser, not in Shoo. A local `wrangler dev` (simulator) serves it on its own host.
    static func pageURL(language: AppLanguage, api: URL = AppConfig.apiBaseURL) -> URL {
        let base = api == AppConfig.cloudAPIURL ? AppConfig.siteURL : api
        var components = URLComponents(url: base.appending(path: "safari-check"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "lang", value: language.code)]
        return components.url!
    }

    /// What `status` says about a check started at `start`; nil while nothing newer than the tap has arrived.
    static func result(of status: ExtensionStatus, since start: Date) -> Result? {
        guard let seen = status.lastSeen, seen >= start else { return nil }
        switch status {
        case .active: return .passed
        case .off(_, .someSitesOnly): return .someSitesOnly
        // Switched off since: not passed yet, keep looking.
        case .off: return nil
        }
    }

    /// Reads the status `times` times, `every` apart, until a fresh heartbeat decides; `notSeen` when none came.
    /// nil when cancelled (the app left the foreground again).
    static func run(
        since start: Date,
        times: Int = recheck.times,
        every: Duration = recheck.every,
        read: () async -> ExtensionStatus
    ) async -> Result? {
        for attempt in 0..<times {
            if attempt > 0 {
                do { try await Task.sleep(for: every) } catch { return nil }
            }
            if let result = result(of: await read(), since: start) { return result }
            if Task.isCancelled { return nil }
        }
        return .notSeen
    }
}

/// Settings first ("Make Safari default"); once the user is back the button turns into "Check & continue", which
/// opens Shoo's check page in the default browser (`SafariCheck`). Back in Shoo the result decides: the success
/// screen, or a toast with what to fix.
struct SafariDefaultView: View {
    let onBack: () -> Void
    let onContinue: () -> Void
    /// The extension status as now (`AppEnvironment.extensionStatus`).
    let readStatus: () async -> ExtensionStatus
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale
    @Environment(\.shooReduceMotion) private var reduceMotion
    @State private var openedSettings = false
    @State private var cameBack = false
    /// When "Check & continue" was tapped: only heartbeats after it count.
    @State private var checkStartedAt: Date?
    @State private var isChecking = false
    /// The check page is opening: the result is read once Shoo is back in front, not before it left.
    @State private var awaitingReturn = false
    @State private var result: SafariCheck.Result?
    @State private var toast: SafariCheckToast?
    @State private var isVideoPresented = false
    @State private var videoStartTime: CMTime = .zero

    private let steps = SafariDefaultSetup.steps(for: ProcessInfo.processInfo.operatingSystemVersion)

    var body: some View {
        OnboardingFormPage(title: "Set Safari as default", onBack: onBack) {
            // Figma "image 1" at y 72.5, the headline right under it at 373; "Step 2 of 2" between them
            // (transition B, 2502:5418), so this screen is not taken for ON-04.
            VStack(spacing: 0) {
                OnboardingHeroImage(name: "SafariDefaultIllustration", top: 10.5, bottom: 0.5)
                OnboardingStepChip(done: 2, count: 2)
                    .padding(.bottom, 8)
            }
        } content: {
            // Figma "stack": 16 between rows, 40 under the headline.
            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    OnboardingStepRow(number: index + 1, text: text(for: step))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 40)
        } footer: {
            footer
        }
        .footerEndsWithLink()
        .largeHeadline()
        // Figma "Frame 2": 354 wide, one line.
        .headlineInset(24)
        // Back from Settings, "Make Safari default" crossfades into "Check & continue".
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.3), value: cameBack)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.3), value: result)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, openedSettings { cameBack = true }
            if phase != .active { awaitingReturn = false }
        }
        // Back from the check page: read now, then a few more times, only for heartbeats after the tap.
        .task(id: CheckKey(phase: scenePhase, startedAt: checkStartedAt, awaitingReturn: awaitingReturn)) {
            guard scenePhase == .active, let start = checkStartedAt, isChecking, !awaitingReturn else { return }
            guard let outcome = await SafariCheck.run(since: start, read: readStatus) else { return }
            isChecking = false
            checkStartedAt = nil
            if outcome == .passed {
                toast = nil
                onContinue()
                return
            }
            result = outcome
            toast = SafariCheckToast(outcome)
        }
        // Where an iOS notification would be, Shoo's head 8 pt under the status bar (as ON-04's F3 toasts).
        .overlay(alignment: .top) {
            if let toast {
                ShooToast(
                    title: L10n.string(toast.title, language: AppLanguage(locale: locale)),
                    line: L10n.string(toast.line, language: AppLanguage(locale: locale)),
                    colors: SettingsReturnToast.colors, pose: toast.pose, identifier: "safariDefault.toast",
                    duration: UIAccessibility.isVoiceOverRunning ? .seconds(10) : .seconds(6),
                    onClose: { self.toast = nil }
                )
                .padding(.top, 8)
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(StateMotion.enter(reduceMotion: reduceMotion), value: toast)
        .fullScreenCover(isPresented: $isVideoPresented) {
            TutorialVideoPlayer(video: .safariDefault, startTime: videoStartTime)
        }
    }

    @ViewBuilder private var footer: some View {
        switch result {
        case .someSitesOnly:
            // Toast B: the fix is in Safari's settings for Shoo; the check page tells the extension again.
            Button("Open Safari settings") { Task { await ExtensionSetup.openSettings() } }
                .buttonStyle(OnboardingCapsuleButtonStyle())
                .transition(.opacity)
                .accessibilityIdentifier("safariDefault.openSafariSettings")
            SafariDefaultPromptLink(prompt: "Changed it?", link: "Check again", action: startCheck)
                .accessibilityIdentifier("safariDefault.checkAgain")
        case .notSeen:
            Button("Try again", action: startCheck)
                .buttonStyle(OnboardingCapsuleButtonStyle())
                .transition(.opacity)
                .accessibilityIdentifier("safariDefault.retry")
            SafariDefaultPromptLink(prompt: "Still not working?", link: "Continue anyway", action: onContinue)
                .accessibilityIdentifier("safariDefault.skip")
        case .passed, nil:
            if cameBack {
                Button(action: startCheck) {
                    ZStack {
                        Text("Check & continue").opacity(isChecking ? 0 : 1)
                        if isChecking { ProgressView().tint(OnboardingTheme.onButton) }
                    }
                }
                .buttonStyle(OnboardingCapsuleButtonStyle())
                .disabled(isChecking)
                .accessibilityValue(isChecking ? Text("Checking") : Text(verbatim: ""))
                .transition(.opacity)
                .accessibilityIdentifier("safariDefault.check")
                SafariDefaultPromptLink(prompt: "Not changed yet?", link: "Open Settings again") {
                    openedSettings = true
                    Task { await SafariDefaultSetup.openSettings() }
                }
                .accessibilityIdentifier("safariDefault.openAgain")
            } else {
                Button("Make Safari default") {
                    openedSettings = true
                    Task { await SafariDefaultSetup.openSettings() }
                }
                .buttonStyle(OnboardingCapsuleButtonStyle())
                .transition(.opacity)
                .accessibilityIdentifier("safariDefault.open")
                OnboardingTutorialLink { watchTutorial() }
                    .accessibilityIdentifier("safariDefault.video")
            }
        }
    }

    /// Step 03 says what the check does once the button is "Check & continue".
    private func text(for step: SafariDefaultSetup.Step) -> LocalizedStringKey {
        if step == .comeBack, cameBack || result != nil {
            return "Tap Check & continue. Shoo opens one page to check, then you come back to Shoo."
        }
        return step.text
    }

    /// "Check & continue", "Check again", "Try again": opens the check page in the default browser.
    private func startCheck() {
        toast = nil
        result = nil
        cameBack = true
        checkStartedAt = Date()
        isChecking = true
        awaitingReturn = true
        Task {
            let opened = await UIApplication.shared.open(SafariCheck.pageURL(language: AppLanguage(locale: locale)))
            // Nothing opened: Shoo never leaves, so the check reads in place (and ends as "couldn't be checked").
            if !opened { awaitingReturn = false }
        }
    }

    /// "Watch the tutorial": straight into PiP so the steps stay on screen; full screen where PiP can't run.
    private func watchTutorial() {
        TutorialPiP.shared.start(
            .safariDefault,
            fallback: {
                videoStartTime = .zero
                isVideoPresented = true
            },
            restore: { time in
                videoStartTime = time
                isVideoPresented = true
            }
        )
    }
}

private struct CheckKey: Equatable {
    let phase: ScenePhase
    let startedAt: Date?
    let awaitingReturn: Bool
}

/// Grey question, blue link (Figma "Belum diganti? Buka Pengaturan lagi"), like "Having trouble? Watch the tutorial".
private struct SafariDefaultPromptLink: View {
    let prompt: LocalizedStringKey
    let link: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(prompt) + Text(verbatim: " ") + Text(link).fontWeight(.semibold).foregroundStyle(OnboardingTheme.link)
        }
        .buttonStyle(OnboardingLinkButtonStyle(color: OnboardingTheme.ink, weight: .regular))
        .transition(.opacity)
    }
}

/// The check's two failures (Figma 2497:4919, branches 8a and 8b), orange like ON-04's F3 toasts.
enum SafariCheckToast: Equatable {
    case someSitesOnly
    case notSeen

    init?(_ result: SafariCheck.Result) {
        switch result {
        case .passed: return nil
        case .someSitesOnly: self = .someSitesOnly
        case .notSeen: self = .notSeen
        }
    }

    var title: String.LocalizationValue {
        switch self {
        case .someSitesOnly: "Shoo is on for some sites only"
        case .notSeen: "Shoo couldn't be checked yet"
        }
    }

    var line: String.LocalizationValue {
        switch self {
        case .someSitesOnly: "In Safari settings, tap All Websites, then choose Allow."
        case .notSeen: "Safari isn't your main browser yet, or Shoo isn't allowed in Safari yet."
        }
    }

    var pose: Mascot {
        switch self {
        case .someSitesOnly: .tapHere
        case .notSeen: .think
        }
    }
}

#Preview {
    SafariDefaultView(onBack: {}, onContinue: {}, readStatus: { .active(lastSeen: nil) })
}

/// "STEP 2 OF 2" above the headline (transition B): a small pill, #E3EEFB with #1F5FAF SF Rounded Semibold 13.
private struct OnboardingStepChip: View {
    let done: Int
    let count: Int

    var body: some View {
        Text("Step \(done) of \(count)")
            .textCase(.uppercase)
            .onboardingFont(13, weight: .semibold, design: .rounded, tracking: 0.4, relativeTo: .footnote)
            .foregroundStyle(Color(hex: 0x1F5FAF))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color(hex: 0xE3EEFB), in: Capsule())
            .accessibilityIdentifier("safariDefault.stepChip")
    }
}
