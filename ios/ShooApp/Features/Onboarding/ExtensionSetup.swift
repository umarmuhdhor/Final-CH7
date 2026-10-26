import SafariServices
import SwiftUI

/// ON-04 instructions. iOS 26.2+ opens Shoo's own extension page, so fewer steps are needed.
/// Settings paths per iOS version are BELUM DIVERIFIKASI on device (spike 01S, S2).
enum ExtensionSetup {
    enum Step: Equatable, CaseIterable {
        case tapTurnOn
        case openSettingsModern
        case openSettingsLegacy
        case switchOn
        case allowEveryWebsite
        case openAWebsite
    }

    static func steps(for version: OperatingSystemVersion) -> [Step] {
        let first: Step
        if (version.majorVersion, version.minorVersion) >= (26, 2) {
            first = .tapTurnOn
        } else if version.majorVersion >= 18 {
            first = .openSettingsModern
        } else {
            first = .openSettingsLegacy
        }
        // iOS 26.2+ reads Safari's switch directly (ExtensionStatus). Before that only a heartbeat tells,
        // and it needs a page load, so the last step sends the user to Safari (S1, BELUM DIVERIFIKASI).
        if first == .tapTurnOn { return [first, .switchOn, .allowEveryWebsite] }
        return [first, .switchOn, .allowEveryWebsite, .openAWebsite]
    }

    /// Bundle ID of the Safari extension: the app's own ID + ".extension" (ios/project.yml). Never hardcoded (L0).
    static var extensionIdentifier: String? {
        Bundle.main.bundleIdentifier.map { $0 + ".extension" }
    }

    /// "Turn on" (PRD ON-04). Never uses `App-prefs:` (mandate: App Review risk).
    @MainActor
    static func openSettings() async {
        if #available(iOS 26.2, *), let identifier = extensionIdentifier {
            do {
                try await SFSafariSettings.openExtensionsSettings(forIdentifiers: [identifier])
                return
            } catch {
                Log.app.error("Opening Safari extension settings failed", error)
            }
        }
        if let url = URL(string: UIApplication.openSettingsURLString) {
            await UIApplication.shared.open(url)
        }
    }

    /// A page of Shoo's own (the privacy policy), so the check sends no visit to anyone else. Any page
    /// Safari loads makes the extension report in, with whether it may read every site (#135).
    static let checkPageURL = AppConfig.apiBaseURL.appending(path: "privacy")

    /// "Open Safari": one page load writes a fresh heartbeat (and `extension.allSites`) to the App Group.
    /// Opens the default browser; Shoo only runs in Safari, which is the default on most iPhones.
    @MainActor
    static func openSafari() async {
        await UIApplication.shared.open(checkPageURL)
    }
}

extension ExtensionSetup.Step {
    var text: LocalizedStringKey {
        switch self {
        case .tapTurnOn: "Tap the button below to open Safari settings."
        case .openSettingsModern: "Open Settings › Apps › Safari › Extensions."
        case .openSettingsLegacy: "Open Settings › Safari › Extensions."
        case .switchOn: "Tap Shoo and switch it on."
        case .allowEveryWebsite: "Tap All Websites and choose Allow, not Ask."
        case .openAWebsite: "Open any website in Safari, then come back here."
        }
    }

    var systemImage: String {
        switch self {
        case .tapTurnOn: "hand.tap.fill"
        case .openSettingsModern, .openSettingsLegacy: "gearshape.fill"
        case .switchOn: "switch.2"
        case .allowEveryWebsite: "checkmark.circle.fill"
        case .openAWebsite: "safari.fill"
        }
    }
}

extension ExtensionStatus.NextStep {
    /// What is wrong, said once, with what to do about it (#135).
    var message: LocalizedStringKey {
        switch self {
        case .switchOn: "Shoo is switched off in Safari. Switch it on to stay safe."
        case .allowEveryWebsite: "Shoo can't check every website yet. In Safari settings, tap All Websites and choose Allow. Already did? Open a website so Shoo can see it."
        case .switchOnThenOpenAWebsite: "Shoo hasn't checked in yet. Switch it on in Safari settings, then open any website in Safari."
        case .openAWebsite: "Almost done. Open any website in Safari so Shoo can check in. Nothing changes? In Safari settings, set All Websites to Allow."
        }
    }

    /// The main button opens Safari only when the switch is known to be on; otherwise Settings comes first.
    var opensSafariFirst: Bool {
        switch self {
        case .allowEveryWebsite, .openAWebsite: true
        case .switchOn, .switchOnThenOpenAWebsite: false
        }
    }

    /// Whether a second, smaller button is worth showing (Settings after Safari, or Safari after Settings).
    var hasSecondAction: Bool { self != .switchOn }
}
