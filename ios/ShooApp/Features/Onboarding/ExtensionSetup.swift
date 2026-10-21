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
        // A heartbeat needs a page load, so the last step sends the user to Safari (S1, BELUM DIVERIFIKASI).
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
}

extension ExtensionSetup.Step {
    var text: LocalizedStringKey {
        switch self {
        case .tapTurnOn: "Tap Turn on below."
        case .openSettingsModern: "Open Settings › Apps › Safari › Extensions."
        case .openSettingsLegacy: "Open Settings › Safari › Extensions."
        case .switchOn: "Tap Shoo and switch it on."
        case .allowEveryWebsite: "Choose Allow for every website."
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
