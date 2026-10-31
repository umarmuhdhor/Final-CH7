import SwiftUI

/// The guardian's word under a row of the own Activity list (PR-05, Figma 450:8734 / 450:8739 /
/// 450:8744): "Menurut Virellia website ini berbahaya!", "… link ini aman. Shoo tetap tak
/// menyarankan …" or "Virellia belum melihat website ini".
enum ActivityNote: Equatable {
    /// `name` nil = the viewer decided themselves ("you").
    case notSafe(name: String?)
    case safe(name: String?)
    case unseen(guardianName: String)

    /// A verdict always shows. Without one, only a blocked scan of a Protected user (one with a
    /// guardian) says the guardian has not looked yet; a warning row stays plain, as in Figma.
    init?(scan: ScanResult, guardianName: String?, viewerDeviceId: String?) {
        if let verdict = scan.verdict {
            let name = verdict.byDeviceId == viewerDeviceId ? nil : verdict.byName
            self = verdict.value == .notSafe ? .notSafe(name: name) : .safe(name: name)
        } else if scan.status == .blocked, let guardianName, !guardianName.isEmpty {
            self = .unseen(guardianName: guardianName)
        } else {
            return nil
        }
    }

    /// Figma (icon, icon circle, stroke, text).
    fileprivate var colors: (icon: Color, circle: Color, stroke: Color, text: Color) {
        switch self {
        case .notSafe:
            (ActivityStyle.hex(0xE5483B), ActivityStyle.hex(0xFFE0DC), ActivityStyle.hex(0xFFCDCD), ActivityStyle.ink)
        case .safe:
            (ActivityStyle.hex(0xFF9500), ActivityStyle.hex(0xFFE1B6), ActivityStyle.hex(0xFFE1B6), ActivityStyle.ink)
        case .unseen:
            (ActivityStyle.hex(0x727272), ActivityStyle.hex(0xE7E7E7), ActivityStyle.separator, ActivityStyle.secondary)
        }
    }

    /// The name is bold (semibold for "unseen"), the rest regular, as in Figma.
    func text(language: AppLanguage) -> Text {
        switch self {
        case .notSafe(let name):
            let who = Text(verbatim: name ?? L10n.string("activity.note.you", language: language)).bold()
            return Text("activity.note.notSafe \(who)")
        case .safe(let name):
            let who = Text(verbatim: name ?? L10n.string("activity.note.you", language: language)).bold()
            return Text("activity.note.safe \(who)")
        case .unseen(let guardianName):
            let who = Text(verbatim: guardianName).fontWeight(.semibold)
            return Text("activity.note.unseen \(who)")
        }
    }
}

/// White strip with an info circle, r 10, 1 pt stroke in the note's colour.
struct ActivityNoteView: View {
    let note: ActivityNote
    let language: AppLanguage

    var body: some View {
        let colors = note.colors
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .activityFont(12)
                .foregroundStyle(colors.icon)
                .frame(width: 21, height: 21)
                .background(colors.circle, in: Circle())
                .accessibilityHidden(true)
            note.text(language: language)
                .activityFont(13, tracking: -0.1625)
                .foregroundStyle(colors.text)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(minHeight: 34)
        .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(colors.stroke))
    }
}

/// Own list: "Diblokir" as Figma's solid red "Red Button" (white text). A blocked site the
/// guardian marked safe keeps the word but turns grey (Figma: the same button in Luminosity).
struct ActivityBlockedPill: View {
    let markedSafe: Bool

    private var colors: [Color] {
        markedSafe
            ? [ActivityStyle.hex(0x474747), ActivityStyle.hex(0x848484)]
            : [ActivityStyle.hex(0xBB1616), ActivityStyle.hex(0xFF4F4F)]
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.circle.fill")
                .activityFont(10, .semibold)
                .accessibilityHidden(true)
            Text("Blocked")
                .activityFont(13, tracking: -0.1625)
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(minHeight: 23)
        .background(LinearGradient(colors: colors, startPoint: .bottom, endPoint: .top), in: Capsule())
        .overlay(Capsule().stroke(colors[0], lineWidth: 0.75))
        .fixedSize()
    }
}

#Preview {
    VStack(spacing: 12) {
        ActivityNoteView(note: .notSafe(name: "Virellia"), language: .indonesian)
        ActivityNoteView(note: .safe(name: "Virellia"), language: .indonesian)
        ActivityNoteView(note: .unseen(guardianName: "Virellia"), language: .indonesian)
        HStack {
            ActivityBlockedPill(markedSafe: false)
            ActivityBlockedPill(markedSafe: true)
        }
    }
    .padding()
    .background(ActivityStyle.background)
    .environment(\.locale, Locale(identifier: "id"))
}
