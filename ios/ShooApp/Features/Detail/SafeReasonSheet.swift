import SwiftUI
import UIKit

/// Why the Guardian overrides Shoo with "Aman" (GD-07). Shoo flagged the site; the Guardian says it is fine.
/// The ids are stable English slugs so Team AI can learn from them (layer 5, #241); the chip text is localized.
enum SafeReason: String, CaseIterable, Identifiable, Sendable {
    case officialSite = "official_site"
    case knownSite = "known_site"
    case usedBefore = "used_before"
    case trustedSender = "trusted_sender"
    case other

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .officialSite: "Official site"
        case .knownSite: "I know this site"
        case .usedBefore: "Used it before, no problems"
        case .trustedSender: "Sent by someone I trust"
        case .other: "Other"
        }
    }
}

/// The `notes` of `POST /verdicts` for a safe override. The contract has only free text (280 characters,
/// contracts/api.md "Verdicts"), so the reasons go first on their own line, then the Guardian's note:
///
///     reasons: official_site, used_before
///     Ini situs resmi bank saya.
enum SafeReasonNotes {
    /// The Guardian's own text (Figma counter "90/200"). With every reason picked the whole stays under 280.
    static let maxNoteLength = 200

    /// The server counts code points (`verdicts.ts` `MAX_NOTES`), not characters: an emoji such as ❤️ or 👍🏽 is
    /// one character but two or more code points. Counting characters let a note of emoji go over 280 (422).
    static func length(_ note: String) -> Int { note.unicodeScalars.count }

    /// `note` cut to `maxNoteLength` code points, at a whole character so no emoji is split.
    static func clamp(_ note: String) -> String {
        guard length(note) > maxNoteLength else { return note }
        var kept = ""
        var count = 0
        for character in note {
            let size = character.unicodeScalars.count
            if count + size > maxNoteLength { break }
            kept.append(character)
            count += size
        }
        return kept
    }

    static func compose(reasons: Set<SafeReason>, note: String) -> String {
        let ids = SafeReason.allCases.filter(reasons.contains).map(\.rawValue)
        let line = "reasons: " + ids.joined(separator: ", ")
        let text = clamp(note.trimmingCharacters(in: .whitespacesAndNewlines))
        return text.isEmpty ? line : line + "\n" + text
    }
}

/// Figma "Sheet · Tandai bahaya" (1668:11234, states 1668:10768 / 1668:11093 / 1668:11261), turned around for
/// "Aman": the Guardian picks at least one reason and may add a note before the site counts as safe.
/// X or a swipe down closes it and drops the input. A failed save keeps the sheet and the input.
/// Presented with `peekSheet` (fase 29g): Shoo peeks over the top edge.
struct SafeReasonSheet: View {
    /// Sends the verdict; `true` once the server saved it (the sheet then closes).
    let onSubmit: @MainActor (String) async -> Bool

    @Environment(\.closePeekSheet) private var close
    @Environment(\.locale) private var locale
    @Environment(\.shooReduceMotion) private var reduceMotion
    /// F1 (goldfish 21 Nov): one more "are you sure?" before a family-wide safe mark that can't be undone for days.
    @State private var isConfirming = false
    @State private var reasons: Set<SafeReason> = []
    @State private var note = ""
    @State private var isSaving = false
    @State private var failed = false
    @State private var height: CGFloat = 600
    /// Height the scroll view got; while the content fits it, the scroll view stays still so a drag moves the sheet.
    @State private var viewport: CGFloat = 0
    @FocusState private var noteFocused: Bool
    /// Screen y of the keyboard's top edge, suggestion bar included; `nil` while it is down. Screen and window
    /// coordinates are the same here: the app is iPhone only, always full screen.
    @State private var keyboardTop: CGFloat?
    /// Screen y of the scroll view's bottom edge, after the room the sheet already made for the keys.
    @State private var scrollBottom: CGFloat = 0

    /// How far the keyboard still reaches into the scroll view.
    private var keyboardOverlap: CGFloat {
        guard let keyboardTop else { return 0 }
        return max(0, scrollBottom - keyboardTop)
    }

    private static let submitID = "safeReason.submit"
    private static let endID = "safeReason.end"

    private var canSubmit: Bool { !reasons.isEmpty && !isSaving }

    /// "Senin, 23 November": the first weekly review after a mark made now (`VerdictLock`).
    private var lockDay: String {
        VerdictLock.unlocksAt(decidedAt: Date()).formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale))
    }

    var body: some View {
        // Scrolls once the keyboard leaves less room than the content needs; the header never clips.
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    content
                    // The very end of the content, under its bottom padding: what the keyboard scroll aims at.
                    Color.clear.frame(height: 1).id(Self.endID)
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
            }
            // Never taller than the content: the card hugs it and the space above stays dimmed. `minHeight: 0` lets
            // it give way when the screen is short.
            .frame(minHeight: 0, maxHeight: height)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewport = $0 }
            // With the keys up it must scroll: the room made for them (contentMargins) is not in `height`.
            .scrollDisabled(keyboardTop == nil && height <= viewport + 0.5)
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            // U-11: "Mark Safe" sat under the keyboard while typing. On iPhone 17 the sheet makes room for the
            // keys and their suggestion bar but stays scrolled to the top; on SE it makes room for less than the
            // keyboard takes. So: room for whatever the keyboard still covers, then scroll the button into view.
            .contentMargins(.bottom, keyboardOverlap, for: .scrollContent)
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { scrollBottom = $0 }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
                keyboardTop = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect)?.minY
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                keyboardTop = nil
            }
            // Once the keyboard and the room above it have settled while typing (keys up, the sheet resized).
            // A new value cancels the wait, so a drag or the resize itself does not queue a scroll per frame.
            .task(id: [keyboardTop ?? -1, scrollBottom, viewport]) {
                guard keyboardTop != nil, noteFocused else { return }
                // Once soon, then again after the keyboard's slide: a scroll made while the sheet is still moving
                // for the keys can be lost (the peek sheet's cover moves with them on some runs, not on others).
                for delay in [300, 450] {
                    try? await Task.sleep(for: .milliseconds(delay))
                    guard !Task.isCancelled else { return }
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
                        proxy.scrollTo(Self.endID, anchor: .bottom)
                    }
                }
            }
        }
        // The grabber the system sheet drew.
        .overlay(alignment: .top) {
            Capsule().fill(ProfileStyle.sheetGrabber).frame(width: 36, height: 5)
                .padding(.top, 8)
                .accessibilityHidden(true)
        }
        .environment(\.colorScheme, .light)
        .peekSheetDismissDisabled(isSaving)
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: failed)
        .sensoryFeedback(.error, trigger: failed) { _, now in now }
        .accessibilityIdentifier("safeReason.sheet")
        // Figma "Dialog Shoo", pose Mikir: the last check before the family-wide mark.
        .shooDialog(isPresented: $isConfirming) {
            ShooDialog(
                pose: .think,
                title: Text("Mark this site safe?"),
                message: Text("It can then be opened on every phone in your family. You can change it again from \(lockDay)."),
                tone: .safe,
                primary: .init(title: Text("Yes, mark safe"), identifier: "safeReason.confirm") {
                    Task { await submit() }
                },
                secondary: .init(title: Text("Cancel"), identifier: "safeReason.confirm.cancel"),
                identifier: "safeReason.confirmDialog"
            )
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Text("Why is it safe?")
                .activityFont(17, .semibold)
                .foregroundStyle(DetailStyle.title)
                .accessibilityAddTraits(.isHeader)
            chips
            Text("Note (optional)")
                .activityFont(17, .semibold)
                .foregroundStyle(DetailStyle.title)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 8) {
                noteField
                HStack(alignment: .top) {
                    Text("Don't write a PIN, OTP or account number.")
                    Spacer(minLength: 12)
                    Text(verbatim: "\(SafeReasonNotes.length(note))/\(SafeReasonNotes.maxNoteLength)")
                        .monospacedDigit()
                        .accessibilityLabel(Text("\(SafeReasonNotes.length(note)) of \(SafeReasonNotes.maxNoteLength) characters"))
                }
                .activityFont(13, rounded: true)
                .foregroundStyle(DetailStyle.secondary)
            }
            if failed { errorBanner }
            // V5: the reason it is grey, on screen and not only for VoiceOver.
            if reasons.isEmpty {
                Text("Pick at least one reason")
                    .activityFont(13, rounded: true)
                    .foregroundStyle(DetailStyle.secondary)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
                    .accessibilityIdentifier("safeReason.pickHint")
            }
            submitButton
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 12)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Mark as safe")
                    .activityFont(28, .semibold)
                    .foregroundStyle(DetailStyle.title)
                    .accessibilityAddTraits(.isHeader)
                Text("Shoo flagged this site. Tell us why it's safe. It helps Shoo block fewer good sites.")
                    .activityFont(16, rounded: true, tracking: -0.31)
                    .foregroundStyle(DetailStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                // plan/alief/family-safe.md: one Guardian's "Aman" counts on every phone of the family, so nobody
                // has to mark the same link again (usability test 20 Nov 2026). F1: and the lock, before saving.
                Label("Applies to every phone in your family. You can't change it until \(lockDay).", systemImage: "person.2.fill")
                    .activityFont(14, rounded: true)
                    .foregroundStyle(DetailStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
                    .accessibilityIdentifier("safeReason.familyNote")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { close() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(DetailStyle.secondary)
                    .frame(width: 30, height: 30)
                    .background(DetailStyle.greyBadgeFill, in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .padding(.top, -7)
            .padding(.trailing, -7)
            .disabled(isSaving)
            .accessibilityLabel(Text("Close"))
            .accessibilityIdentifier("safeReason.close")
        }
    }

    private var chips: some View {
        // Figma "Chips alasan": wrapping row, 8 pt apart both ways.
        FlowLayout(spacing: 8) {
            ForEach(SafeReason.allCases) { reason in
                let selected = reasons.contains(reason)
                Button {
                    if selected { reasons.remove(reason) } else { reasons.insert(reason) }
                } label: {
                    Text(reason.label)
                        .activityFont(16, rounded: true, tracking: -0.31)
                        .foregroundStyle(selected ? SafeReasonStyle.chipText : DetailStyle.title)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(selected ? SafeReasonStyle.chipFill : .white, in: Capsule())
                        .overlay(
                            Capsule().strokeBorder(
                                selected ? SafeReasonStyle.chipStroke : SafeReasonStyle.chipIdleStroke,
                                lineWidth: selected ? 1.5 : 1
                            )
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
                .accessibilityIdentifier("safeReason.chip.\(reason.rawValue)")
            }
        }
        .sensoryFeedback(.selection, trigger: reasons)
    }

    private var noteField: some View {
        TextField(
            "",
            text: $note,
            prompt: Text("e.g. This is my bank's real site, I checked the address.")
                .foregroundStyle(DetailStyle.secondary.opacity(0.8)),
            axis: .vertical
        )
        .activityFont(16, rounded: true, tracking: -0.31)
        .foregroundStyle(DetailStyle.title)
        .lineLimit(3, reservesSpace: true)
        .focused($noteFocused)
        .onChange(of: note) { _, new in
            let clamped = SafeReasonNotes.clamp(new)
            if clamped != new { note = clamped }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(minHeight: 96, alignment: .topLeading)
        // Figma: grey and borderless while empty and idle, white with a blue rim while typing.
        .background(noteFocused ? .white : DetailStyle.cardFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(noteFocused ? SafeReasonStyle.focus : .clear, lineWidth: 1.5)
        )
        .accessibilityLabel(Text("Note (optional)"))
        .accessibilityIdentifier("safeReason.note")
    }

    /// Figma 1668:11261 "Gagal menyimpan": the input stays, the button becomes "Coba lagi".
    private var errorBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.arrow.circlepath")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(SafeReasonStyle.errorIcon)
                .frame(width: 32, height: 32)
                .background(DetailStyle.scamIconFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Couldn't save")
                    .activityFont(15, .semibold)
                    .foregroundStyle(DetailStyle.ink)
                Text("Check your connection. Your note isn't lost.")
                    .activityFont(13, rounded: true)
                    .foregroundStyle(DetailStyle.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(SafeReasonStyle.chipIdleStroke))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("safeReason.error")
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 4)))
    }

    private var submitButton: some View {
        Button {
            noteFocused = false
            // "Try again" after a failed save: they already said yes.
            if failed { Task { await submit() } } else { isConfirming = true }
        } label: {
            HStack(spacing: 8) {
                if isSaving {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: failed ? "arrow.clockwise" : "checkmark.circle.fill")
                }
                Text(failed ? "Try again" : "Mark Safe")
            }
            .activityFont(17, .semibold)
            .foregroundStyle(reasons.isEmpty ? SafeReasonStyle.disabledText : .white)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background {
                // V5: grey and flat while no reason is picked (pale green still read as enabled).
                if reasons.isEmpty {
                    Capsule().fill(SafeReasonStyle.disabledFill)
                } else {
                    Capsule().fill(LinearGradient(
                        colors: [SafeReasonStyle.buttonTop, SafeReasonStyle.buttonBottom], startPoint: .bottom, endPoint: .top
                    ))
                    .overlay(Capsule().strokeBorder(SafeReasonStyle.buttonTop, lineWidth: 1.5))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
        .padding(.top, 4)
        .accessibilityHint(reasons.isEmpty ? Text("Pick at least one reason first") : Text(""))
        .accessibilityIdentifier("safeReason.submit")
        .id(Self.submitID)
    }

    private func submit() async {
        guard canSubmit else { return }
        noteFocused = false
        isSaving = true
        let saved = await onSubmit(SafeReasonNotes.compose(reasons: reasons, note: note))
        isSaving = false
        if saved { close() } else { failed = true }
    }
}

/// Green mirror of the Figma red "Tandai Bahaya" sheet. White on `buttonTop` is 4.6:1.
enum SafeReasonStyle {
    static let chipFill = DetailStyle.safeIconFill
    static let chipStroke = DetailStyle.safeIcon
    static let chipText = DetailStyle.hex(0x1A7F37)
    static let chipIdleStroke = DetailStyle.hex(0xE3E7ED)
    static let focus = DetailStyle.hex(0x3866ED)
    static let buttonTop = DetailStyle.hex(0x1A7F37)
    static let buttonBottom = DetailStyle.hex(0x2DA44E)
    static let errorIcon = DetailStyle.hex(0xC81414)
    /// V5 disabled button: #E3E7ED with #6B7280 text (WCAG exempts disabled controls from contrast).
    static let disabledFill = DetailStyle.hex(0xE3E7ED)
    static let disabledText = DetailStyle.hex(0x6B7280)
}

/// Left-aligned wrapping row (Figma auto layout "WRAP").
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.init(width: bounds.width, height: nil))
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: .init(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.init(width: width, height: nil))
            let next = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if !row.indices.isEmpty, next > width {
                rows.append(row)
                row = Row()
            }
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}
