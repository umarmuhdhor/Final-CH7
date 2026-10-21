import SwiftUI

/// What a scan's chip says (Activity rows, Detail DT-02/DT-06).
enum ScanBadge: Equatable, Sendable {
    case warning
    case blocked
    case verifiedScam
    case markedSafe

    /// A guardian's verdict wins over the detection status.
    init(scan: ScanResult) {
        switch scan.verdict?.value {
        case .notSafe: self = .verifiedScam
        case .safe: self = .markedSafe
        case nil: self = scan.status == .blocked ? .blocked : .warning
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .warning: "Warning"
        case .blocked: "Blocked"
        case .verifiedScam: "Verified scam"
        case .markedSafe: "Marked safe"
        }
    }

    var systemImage: String {
        switch self {
        case .warning: "exclamationmark.triangle.fill"
        case .blocked: "hand.raised.fill"
        case .verifiedScam: "xmark.octagon.fill"
        case .markedSafe: "checkmark.seal.fill"
        }
    }

    var color: Color {
        switch self {
        case .warning: .orange
        case .blocked, .verifiedScam: .red
        case .markedSafe: .green
        }
    }
}

/// Small capsule with icon + label. Colour is never the only signal: the text is always there.
struct StatusChip: View {
    let badge: ScanBadge

    var body: some View {
        Label {
            Text(badge.title)
        } icon: {
            Image(systemName: badge.systemImage)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(badge.color)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(badge.color.opacity(0.15), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    VStack(alignment: .leading) {
        StatusChip(badge: .warning)
        StatusChip(badge: .blocked)
        StatusChip(badge: .verifiedScam)
        StatusChip(badge: .markedSafe)
    }
    .padding()
}
