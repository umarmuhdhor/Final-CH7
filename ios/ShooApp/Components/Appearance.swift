import SwiftUI
import UIKit

/// PF-01 "Pengaturan/Tema": Terang, Gelap, Otomatis (follows the iPhone).
enum AppTheme: String, CaseIterable {
    case light, dark, system

    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .light: .light
        case .dark: .dark
        case .system: .unspecified
        }
    }
}

/// PF-01 "Pengaturan/Aksesibilitas" text size slider: five stops. "Standard" keeps the iPhone's own size.
enum TextSizeLevel: Int, CaseIterable {
    case small, standard, large, larger, largest

    /// nil: no override, the iPhone setting applies.
    var category: UIContentSizeCategory? {
        switch self {
        case .small: .small
        case .standard: nil
        case .large: .extraLarge
        case .larger: .extraExtraLarge
        case .largest: .extraExtraExtraLarge
        }
    }

    var title: String.LocalizationValue {
        switch self {
        case .small: "Small"
        case .standard: "Standard"
        case .large: "Large"
        case .larger: "Large text"
        case .largest: "Largest"
        }
    }
}

extension Color {
    /// A colour that follows the theme and Increase Contrast (the app's own switch or the iPhone's).
    static func dynamic(_ light: UInt32, dark: UInt32, contrastLight: UInt32? = nil, contrastDark: UInt32? = nil) -> Color {
        Color(UIColor { traits in
            let high = traits.accessibilityContrast == .high
            let hex = traits.userInterfaceStyle == .dark
                ? (high ? contrastDark ?? dark : dark)
                : (high ? contrastLight ?? light : light)
            return UIColor(hex: hex)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: Motion and glass

private struct ReduceMotionKey: EnvironmentKey {
    static let defaultValue = false
}

private struct ReduceGlassKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// "Kurangi gerakan" in Shoo, or Reduce Motion on the iPhone.
    var shooReduceMotion: Bool {
        get { self[ReduceMotionKey.self] }
        set { self[ReduceMotionKey.self] = newValue }
    }

    /// "Kurangi efek kaca" in Shoo, or Reduce Transparency on the iPhone: solid instead of glass.
    var shooReduceGlass: Bool {
        get { self[ReduceGlassKey.self] }
        set { self[ReduceGlassKey.self] = newValue }
    }
}

/// Puts the in-app appearance choices on the window scene as trait overrides, so every screen,
/// sheet, UIKit view and dynamic colour sees them (iOS 17 `traitOverrides`).
struct AppearanceOverrides: UIViewRepresentable {
    let theme: AppTheme
    let textSize: TextSizeLevel
    let boldText: Bool
    let highContrast: Bool

    func makeUIView(context: Context) -> Probe { Probe() }

    func updateUIView(_ view: Probe, context: Context) {
        view.overrides = self
        view.apply()
    }

    final class Probe: UIView {
        var overrides: AppearanceOverrides?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            apply()
        }

        func apply() {
            guard let overrides, let scene = window?.windowScene else { return }
            scene.traitOverrides.userInterfaceStyle = overrides.theme.interfaceStyle
            if let category = overrides.textSize.category {
                scene.traitOverrides.preferredContentSizeCategory = category
            } else if scene.traitOverrides.contains(UITraitPreferredContentSizeCategory.self) {
                scene.traitOverrides.remove(UITraitPreferredContentSizeCategory.self)
            }
            if overrides.boldText {
                scene.traitOverrides.legibilityWeight = .bold
            } else if scene.traitOverrides.contains(UITraitLegibilityWeight.self) {
                scene.traitOverrides.remove(UITraitLegibilityWeight.self)
            }
            if overrides.highContrast {
                scene.traitOverrides.accessibilityContrast = .high
            } else if scene.traitOverrides.contains(UITraitAccessibilityContrast.self) {
                scene.traitOverrides.remove(UITraitAccessibilityContrast.self)
            }
        }
    }
}

// MARK: Haptics and read-aloud

/// "Getar" and "Bacakan peringatan" (Pengaturan/Aksesibilitas, "Saat ada peringatan").
enum WarningFeedback {
    /// A warning reached the user inside the app (push while open, a Detail opened from a push).
    @MainActor
    static func warn(settings: AppSettings) {
        guard settings.haptics else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    /// VoiceOver reads the score and the reasons when a warning opens.
    @MainActor
    static func readAloud(settings: AppSettings, text: String) {
        guard settings.readAloud, UIAccessibility.isVoiceOverRunning else { return }
        UIAccessibility.post(notification: .announcement, argument: text)
    }
}
