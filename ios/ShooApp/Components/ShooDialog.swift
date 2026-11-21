import SwiftUI

/// Figma "Dialog Shoo" (`2428:12706`): every "are you sure?" and action error in the app. A pose of the owl
/// peeks from behind a white card over a dimmed screen; a short title, one sentence on what happens, a filled
/// main button and an outlined second button. The main button's colour follows the action: green when it
/// keeps the user safe, blue when neutral, red when it removes something.
struct ShooDialog {
    enum Tone: Equatable {
        case safe, neutral, danger
    }

    struct Action {
        var title: Text
        var identifier: String
        /// `false` keeps the dialog up (with a spinner while `isWorking`) until the caller closes it, for
        /// actions that can fail. `true` closes it first, then runs the action.
        var closes = true
        /// Second button only: red outline for a way out that warns ("Not my family"), instead of grey.
        var warns = false
        var run: () -> Void = {}
    }

    var pose: Mascot
    var title: Text
    var message: Text?
    var tone: Tone = .neutral
    var primary: Action
    /// Cancel-like. Always closes the dialog first.
    var secondary: Action?
    var isWorking = false
    var identifier = "shooDialog"
}

extension View {
    /// Shows `dialog` over everything, sheets included, while `isPresented` is true.
    /// The caller sets `isPresented = false` to close it (the dialog also does after its buttons).
    func shooDialog(isPresented: Binding<Bool>, dialog: @escaping () -> ShooDialog) -> some View {
        modifier(ShooDialogModifier(isPresented: isPresented, dialog: dialog))
    }

    /// One-button error dialog (Figma "Gagal menyimpan", pose Maaf) while `message` is set; `close` clears it.
    /// The messages read "Couldn't save. Check your connection and try again.": the first sentence becomes the
    /// title, the rest the line under it.
    func shooErrorDialog(_ message: String?, close: @escaping () -> Void) -> some View {
        shooDialog(isPresented: Binding(get: { message != nil }, set: { if !$0 { close() } })) {
            .error(message ?? "")
        }
    }
}

extension ShooDialog {
    /// Figma "Gagal menyimpan" (2439:12877): pose Maaf, one "OK". A screen that also confirms something shows
    /// this in the same dialog, since only one cover can be up at a time.
    static func error(_ message: String) -> ShooDialog {
        let parts = errorParts(message)
        return ShooDialog(
            pose: .sorry,
            title: Text(verbatim: parts.title),
            message: parts.detail.map { Text(verbatim: $0) },
            primary: .init(title: Text("OK"), identifier: "shooDialog.ok"),
            identifier: "shooDialog.error"
        )
    }

    /// "Couldn't save. Check your connection." → ("Couldn't save", "Check your connection.").
    /// One sentence stays whole as the title.
    static func errorParts(_ message: String) -> (title: String, detail: String?) {
        guard let range = message.range(of: ". ") else { return (message, nil) }
        let detail = message[range.upperBound...].trimmingCharacters(in: .whitespaces)
        return (String(message[..<range.lowerBound]), detail.isEmpty ? nil : detail)
    }
}

/// A full-screen cover, so the dim covers the tab bar and any sheet. The system slide-up is turned off;
/// the dim fades and the card pops in instead (a plain fade with Reduce Motion).
private struct ShooDialogModifier: ViewModifier {
    @Binding var isPresented: Bool
    let dialog: () -> ShooDialog
    @State private var isCovering = false
    @State private var isVisible = false
    @Environment(\.locale) private var locale
    @Environment(\.shooReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $isCovering) {
                ShooDialogHost(dialog: dialog(), isVisible: isVisible, reduceMotion: reduceMotion) {
                    isPresented = false
                }
                .presentationBackground(.clear)
                .environment(\.locale, locale)
                .environment(\.shooReduceMotion, reduceMotion)
                .onAppear {
                    withAnimation(Self.appear(reduceMotion)) { isVisible = true }
                }
            }
            .onChange(of: isPresented, initial: true) { _, shown in
                shown ? show() : hide()
            }
    }

    private func show() {
        guard !isCovering else { return }
        var noSlide = Transaction()
        noSlide.disablesAnimations = true
        withTransaction(noSlide) { isCovering = true }
    }

    private func hide() {
        guard isCovering else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            isVisible = false
        } completion: {
            var noSlide = Transaction()
            noSlide.disablesAnimations = true
            withTransaction(noSlide) { isCovering = false }
        }
    }

    static func appear(_ reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.34, dampingFraction: 0.78)
    }
}

private struct ShooDialogHost: View {
    let dialog: ShooDialog
    let isVisible: Bool
    let reduceMotion: Bool
    let close: () -> Void
    @AccessibilityFocusState private var isTitleFocused: Bool

    // Figma: dialog 338 wide (32 in from a 402 pt screen), owl 150 tall, the card starting 92 below its top.
    private static let maxWidth: CGFloat = 338
    private static let poseHeight: CGFloat = 150
    private static let cardOverlap: CGFloat = 58

    var body: some View {
        ZStack {
            // Figma "Redup": black 35 %.
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .opacity(isVisible ? 1 : 0)
                .accessibilityHidden(true)
            VStack(spacing: -Self.cardOverlap) {
                MascotImage(pose: dialog.pose, height: Self.poseHeight)
                    // Peeks up from behind the card.
                    .offset(y: isVisible || reduceMotion ? 0 : 24)
                card
            }
            .frame(maxWidth: Self.maxWidth)
            .padding(.horizontal, 24)
            .scaleEffect(isVisible || reduceMotion ? 1 : 0.92)
            .opacity(isVisible ? 1 : 0)
        }
        .onAppear { isTitleFocused = true }
    }

    private var card: some View {
        VStack(spacing: 0) {
            dialog.title
                .profileFont(20, .bold)
                .foregroundStyle(ShooDialogStyle.title)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($isTitleFocused)
            if let message = dialog.message {
                message
                    .profileFont(15)
                    .figmaLineHeight(21, relativeTo: .subheadline)
                    .foregroundStyle(ShooDialogStyle.message)
                    .padding(.top, 8)
            }
            VStack(spacing: 12) {
                Button {
                    if dialog.primary.closes { close() }
                    dialog.primary.run()
                } label: {
                    ZStack {
                        Text(verbatim: " ").hidden()
                        if dialog.isWorking {
                            ProgressView().tint(.white).transition(.opacity)
                        } else {
                            dialog.primary.title.transition(.opacity)
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: dialog.isWorking)
                }
                .buttonStyle(ShooDialogButtonStyle(kind: .filled(dialog.tone)))
                .disabled(dialog.isWorking)
                .accessibilityIdentifier(dialog.primary.identifier)
                if let secondary = dialog.secondary {
                    Button {
                        close()
                        secondary.run()
                    } label: {
                        secondary.title
                    }
                    .buttonStyle(ShooDialogButtonStyle(kind: .outlined(warns: secondary.warns)))
                    .disabled(dialog.isWorking)
                    .accessibilityIdentifier(secondary.identifier)
                }
            }
            .padding(.top, 22)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(EdgeInsets(top: 28, leading: 24, bottom: 24, trailing: 24))
        .frame(maxWidth: .infinity)
        .background(ShooDialogStyle.card, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        // Figma: #0D1A40 18 %, y 12, blur 32.
        .shadow(color: Color(hex: 0x0D1A40, opacity: 0.18), radius: 16, y: 12)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) {
            guard !dialog.isWorking else { return }
            close()
            dialog.secondary?.run()
        }
        .accessibilityIdentifier(dialog.identifier)
    }
}

enum ShooDialogStyle {
    static let card = Color.dynamic(0xFFFFFF, dark: 0x1B1F26)
    static let title = Color.dynamic(0x111827, dark: 0xF7F8FA, contrastLight: 0x000000)
    static let message = Color.dynamic(0x6B7280, dark: 0xA3AAB6, contrastLight: 0x3F4652)
    static let outline = Color.dynamic(0x6B7280, dark: 0x9EA6B4, contrastLight: 0x3F4652)
    /// Figma "Bukan keluarga saya": #DC2626 text and stroke.
    static let warningOutline = Color.dynamic(0xDC2626, dark: 0xF87171, contrastLight: 0xB91C1C)

    /// Figma main buttons run left to right.
    static func fill(_ tone: ShooDialog.Tone) -> LinearGradient {
        let (from, to): (UInt32, UInt32) = switch tone {
        case .safe: (0x17834A, 0x22A35E)
        case .neutral: (0x2954AD, 0x3373D9)
        case .danger: (0xC72121, 0xE54038)
        }
        return LinearGradient(colors: [Color(hex: from), Color(hex: to)], startPoint: .leading, endPoint: .trailing)
    }
}

/// Figma: 52 pt, radius 26, SF Pro Semibold 17. Filled casts #1A3380 18 %, y 6, blur 14.
private struct ShooDialogButtonStyle: ButtonStyle {
    enum Kind {
        case filled(ShooDialog.Tone)
        case outlined(warns: Bool)
    }

    let kind: Kind
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .profileFont(17, .semibold)
            .foregroundStyle(ink)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background { background }
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var ink: Color {
        switch kind {
        case .filled: .white
        case .outlined(let warns): warns ? ShooDialogStyle.warningOutline : ShooDialogStyle.outline
        }
    }

    @ViewBuilder private var background: some View {
        switch kind {
        case .filled(let tone):
            Capsule().fill(ShooDialogStyle.fill(tone))
                .shadow(color: Color(hex: 0x1A3380, opacity: 0.18), radius: 7, y: 6)
        case .outlined:
            Capsule().strokeBorder(ink, lineWidth: 1.5)
                .opacity(isEnabled ? 1 : 0.5)
        }
    }
}

#Preview("Dialog") {
    @Previewable @State var shown = true
    Button("Show") { shown = true }
        .shooDialog(isPresented: $shown) {
            ShooDialog(
                pose: .shock,
                title: Text(verbatim: "Putuskan koneksi dengan Dad?"),
                message: Text(verbatim: "Kamu tidak lagi menerima peringatan dari Dad. Dad akan diberi tahu."),
                tone: .danger,
                primary: .init(title: Text(verbatim: "Ya, putuskan"), identifier: "p"),
                secondary: .init(title: Text(verbatim: "Batal"), identifier: "s")
            )
        }
}
