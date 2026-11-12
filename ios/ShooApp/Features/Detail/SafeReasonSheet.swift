import SwiftUI

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

    static func compose(reasons: Set<SafeReason>, note: String) -> String {
        let ids = SafeReason.allCases.filter(reasons.contains).map(\.rawValue)
        let line = "reasons: " + ids.joined(separator: ", ")
        let text = String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxNoteLength))
        return text.isEmpty ? line : line + "\n" + text
    }
}

/// Figma "Sheet · Tandai bahaya" (1668:11234, states 1668:10768 / 1668:11093 / 1668:11261), turned around for
/// "Aman": the Guardian picks at least one reason and may add a note before the site counts as safe.
/// X or a swipe down closes it and drops the input. A failed save keeps the sheet and the input.
struct SafeReasonSheet: View {
    /// Sends the verdict; `true` once the server saved it (the sheet then closes).
    let onSubmit: @MainActor (String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.shooReduceMotion) private var reduceMotion
    @State private var reasons: Set<SafeReason> = []
    @State private var note = ""
    @State private var isSaving = false
    @State private var failed = false
    @State private var height: CGFloat = 600
    @FocusState private var noteFocused: Bool

    private var canSubmit: Bool { !reasons.isEmpty && !isSaving }

    var body: some View {
        // Scrolls once the keyboard leaves less room than the content needs; the header never clips.
        ScrollView {
            content
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .presentationDetents([.height(height)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
        .presentationBackground(.white)
        .environment(\.colorScheme, .light)
        .interactiveDismissDisabled(isSaving)
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: failed)
        .sensoryFeedback(.error, trigger: failed) { _, now in now }
        .accessibilityIdentifier("safeReason.sheet")
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
                    Text(verbatim: "\(note.count)/\(SafeReasonNotes.maxNoteLength)")
                        .monospacedDigit()
                        .accessibilityLabel(Text("\(note.count) of \(SafeReasonNotes.maxNoteLength) characters"))
                }
                .activityFont(13, rounded: true)
                .foregroundStyle(DetailStyle.secondary)
            }
            if failed { errorBanner }
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
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { dismiss() } label: {
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
            if new.count > SafeReasonNotes.maxNoteLength {
                note = String(new.prefix(SafeReasonNotes.maxNoteLength))
            }
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
            Task { await submit() }
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
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                Capsule().fill(LinearGradient(
                    colors: [SafeReasonStyle.buttonTop, SafeReasonStyle.buttonBottom], startPoint: .bottom, endPoint: .top
                ))
            )
            .overlay(Capsule().strokeBorder(SafeReasonStyle.buttonTop, lineWidth: 1.5))
            // Figma: the button fades until at least one reason is picked.
            .opacity(reasons.isEmpty ? 0.35 : 1)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
        .padding(.top, 4)
        .accessibilityHint(reasons.isEmpty ? Text("Pick at least one reason first") : Text(""))
        .accessibilityIdentifier("safeReason.submit")
    }

    private func submit() async {
        guard canSubmit else { return }
        noteFocused = false
        isSaving = true
        let saved = await onSubmit(SafeReasonNotes.compose(reasons: reasons, note: note))
        isSaving = false
        if saved { dismiss() } else { failed = true }
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
