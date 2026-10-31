import SwiftUI

/// Which empty Activity the user sees (Figma "Aktivitas · Semua / Waspada / Diblokir · Kosong" and
/// "· Perlindungan mati"). Pure, so the rule is testable without views.
enum ActivityEmptyKind: Equatable {
    case all
    case warning
    case blocked
    /// Nothing to show *because* nothing is checked: grey shield and one button to turn Shoo on.
    case protectionOff

    /// Off wins over the filter: an empty list with the extension off says nothing about safety.
    /// Family Activity lists other people's scans, so this iPhone's extension doesn't decide there.
    static func of(filter: ActivityFilter, family: Bool, extensionStatus: ExtensionStatus?) -> ActivityEmptyKind {
        if !family, let extensionStatus, !extensionStatus.isActive { return .protectionOff }
        switch filter {
        case .all: return .all
        case .warning: return .warning
        case .blocked: return .blocked
        }
    }

    /// Figma: the empty block's top below the list's usual 32 pt gap under the segments; differs per
    /// kind so the centre stays put.
    var topPadding: CGFloat {
        switch self {
        case .all, .blocked: 103
        case .warning: 93
        case .protectionOff: 83
        }
    }
}

/// Texts of the status pill and the "off since" line, from what the extension wrote (#183).
enum ActivityEmptyText {
    /// Semua: "Ekstensi Safari aktif". Waspada / Diblokir: "1.284 situs diperiksa · terakhir 10.42 WIB",
    /// shorter when the extension hasn't written the time or the count yet.
    static func pill(
        kind: ActivityEmptyKind, stats: CheckStats, now: Date = Date(),
        language: AppLanguage, timeZone: TimeZone = .current
    ) -> String {
        let extensionOn = L10n.string("Safari extension on", language: language)
        guard kind == .warning || kind == .blocked, let checked = stats.checked else { return extensionOn }
        let count = checked.formatted(.number.locale(language.locale))
        guard let last = stats.lastCheckedAt else {
            return L10n.string("\(count) sites checked", language: language)
        }
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let time = calendar.isDate(last, inSameDayAs: now)
            ? Formatters.time(last, language: language, timeZone: timeZone)
            : Formatters.dayAndTime(last, now: now, language: language, timeZone: timeZone)
        return L10n.string("\(count) sites checked · last at \(time)", language: language)
    }

    /// "Mati sejak 2 hari lalu" / "Off for 2 days", from the last heartbeat; nil when it never ran.
    static func offSince(_ lastSeen: Date?, now: Date = Date(), language: AppLanguage) -> String? {
        guard let lastSeen else { return nil }
        let formatter = DateComponentsFormatter()
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = language.locale
        formatter.calendar = calendar
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 1
        formatter.allowedUnits = [.day, .hour, .minute]
        let interval = max(60, now.timeIntervalSince(lastSeen))
        guard let span = formatter.string(from: interval) else { return nil }
        return L10n.string("Off for \(span)", language: language)
    }
}

/// Figma "Empty State" (480:5500 / 5530 / 5560 / 5590): shield, title, message, then a status pill,
/// or the "Aktifkan ekstensi" button with "Mati sejak …" when protection is off.
struct ActivityEmptyState: View {
    let kind: ActivityEmptyKind
    /// nil hides the pill (Family Activity: this iPhone's extension says nothing about the members).
    let pill: String?
    let offSince: String?
    var turnOn: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            HalftoneShield(isOn: kind != .protectionOff)
            VStack(spacing: 8) {
                Text(title)
                    .activityFont(22, .semibold, tracking: -0.22)
                    .foregroundStyle(ActivityStyle.emptyTitle)
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .activityFont(15)
                    .lineSpacing(3)
                    .foregroundStyle(ActivityStyle.secondary)
                    // Figma 296 pt in SF Pro Display; the app's SF Text runs wider, so the lines break alike at 326.
                    .frame(maxWidth: 326)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 10)
            // One VoiceOver stop for the words; the pill and button stay their own.
            .accessibilityElement(children: .combine)

            if kind == .protectionOff {
                VStack(spacing: 8) {
                    Button(action: turnOn) {
                        Label { Text("Turn on extension") } icon: { Image(systemName: "safari.fill") }
                    }
                    .buttonStyle(ActivityBlueButtonStyle())
                    .accessibilityIdentifier("activity.turnOn")
                    if let offSince {
                        Text(offSince)
                            .activityFont(13, rounded: true)
                            .foregroundStyle(ActivityStyle.secondary)
                            .accessibilityIdentifier("activity.offSince")
                    }
                }
                .padding(.top, 34)
            } else if let pill {
                ActivityStatusPill(text: pill)
                    .padding(.top, 22)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, kind.topPadding)
        // The caller's identifier lands on this container, not on every child.
        .accessibilityElement(children: .contain)
    }

    private var title: LocalizedStringKey {
        switch kind {
        case .all: "No activity yet"
        case .warning: "Nothing suspicious"
        case .blocked: "No sites blocked yet"
        case .protectionOff: "Protection is off"
        }
    }

    private var message: LocalizedStringKey {
        switch kind {
        case .all: "Suspicious sites found while you browse in Safari will show up here."
        case .warning: "The sites you opened lately look safe. We'll let you know if anything seems off."
        case .blocked: "Shoo blocks scam sites automatically before the page can open."
        case .protectionOff: "Shoo's Safari extension is off, so the sites you open aren't checked."
        }
    }
}

/// Figma "Status Pill": green dot + text on 72 % white, white hairline, soft shadow.
private struct ActivityStatusPill: View {
    let text: String

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(ActivityStyle.activeDot)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(verbatim: text)
                .activityFont(13, rounded: true)
                .foregroundStyle(ActivityStyle.secondary)
        }
        .padding(.leading, 12)
        .padding(.trailing, 13)
        .padding(.vertical, 7)
        .background(.white.opacity(0.72), in: Capsule())
        .overlay(Capsule().stroke(.white))
        .shadow(color: ActivityStyle.pillShadow.opacity(0.05), radius: 4, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("activity.statusPill")
    }
}

/// Figma "Button / Blue Button / Primary": blue gradient capsule, 1.5 pt stroke, white icon + label.
private struct ActivityBlueButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(BlueButtonLabelStyle())
            .padding(.leading, 16)
            .padding(.trailing, 20)
            .padding(.vertical, 12)
            .frame(minHeight: 46)
            .background(
                LinearGradient(
                    colors: [ActivityStyle.blueButtonTop, ActivityStyle.blueButtonBottom],
                    startPoint: .top, endPoint: .bottom
                ),
                in: Capsule()
            )
            .overlay(Capsule().stroke(ActivityStyle.blueButtonStroke, lineWidth: 1.5))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

private struct BlueButtonLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon
                .activityFont(19, .semibold)
                .frame(width: 22, height: 22)
            configuration.title
                .activityFont(15, .semibold, tracking: -0.19)
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.2), radius: 2, y: 4)
    }
}

#Preview {
    ScrollView {
        ActivityEmptyState(kind: .warning, pill: "1.284 situs diperiksa · terakhir 10.42 WIB", offSince: nil)
        ActivityEmptyState(kind: .protectionOff, pill: nil, offSince: "Mati sejak 2 hari lalu")
    }
    .background(ActivityBackground())
}
