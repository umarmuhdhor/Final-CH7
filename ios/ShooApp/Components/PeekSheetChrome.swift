import SwiftUI

// Sheets with Shoo peeking over the top edge (fase 29g, Figma "alief notif" 2447:13710): the body sits behind the
// sheet's edge, the fingers in front of it with a thin shadow.
//
// Not a system `.sheet`: on iOS 26 a sheet keeps its glass platter even with a clear background, which would show
// round the mascot. So `peekSheet` presents a clear full-screen cover (without its slide) and draws the rest itself:
// the dimming, the white card with its grabber and corners, the slide up, drag to dismiss, and a tap on the dimming.
// The cover keeps VoiceOver inside the sheet; the escape gesture closes it.

extension View {
    /// Like `.sheet(isPresented:onDismiss:content:)`, with Shoo peeking over the card. Inside, close with
    /// `@Environment(\.closePeekSheet)` (not `dismiss`, which would skip the slide down).
    /// `background`: the card's colour (white by default; a dynamic colour follows dark mode).
    func peekSheet<Sheet: View>(
        isPresented: Binding<Bool>,
        background: Color = .white,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Sheet
    ) -> some View {
        modifier(PeekSheetPresenter(isPresented: isPresented, background: background, onDismiss: onDismiss, sheet: content))
    }
}

extension View {
    /// Like `.sheet(item:onDismiss:content:)`, with Shoo peeking over the card. The last item stays on the card
    /// while it slides down.
    func peekSheet<Item: Identifiable, Sheet: View>(
        item: Binding<Item?>,
        background: Color = .white,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Sheet
    ) -> some View {
        modifier(PeekSheetItemPresenter(item: item, background: background, onDismiss: onDismiss, sheet: content))
    }
}

private struct PeekSheetItemPresenter<Item: Identifiable, Sheet: View>: ViewModifier {
    @Binding var item: Item?
    let background: Color
    let onDismiss: (() -> Void)?
    @ViewBuilder let sheet: (Item) -> Sheet
    @State private var lastItem: Item?

    func body(content: Content) -> some View {
        content
            .peekSheet(
                isPresented: Binding(get: { item != nil }, set: { if !$0 { item = nil } }),
                background: background,
                onDismiss: onDismiss
            ) {
                if let shown = item ?? lastItem { sheet(shown) }
            }
            .onChange(of: item?.id, initial: true) { _, _ in
                if let item { lastItem = item }
            }
    }
}

extension EnvironmentValues {
    /// Slides the peek sheet down, then closes it, even while `peekSheetDismissDisabled`. Does nothing outside a
    /// peek sheet.
    @Entry var closePeekSheet: @MainActor () -> Void = {}
}

extension View {
    /// Like `interactiveDismissDisabled`: no drag, tap on the dimming or escape closes the peek sheet (e.g. while
    /// saving). `closePeekSheet` still does.
    func peekSheetDismissDisabled(_ disabled: Bool = true) -> some View {
        preference(key: PeekSheetDismissDisabledKey.self, value: disabled)
    }
}

private struct PeekSheetDismissDisabledKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

private struct PeekSheetPresenter<Sheet: View>: ViewModifier {
    @Binding var isPresented: Bool
    let background: Color
    let onDismiss: (() -> Void)?
    @ViewBuilder let sheet: () -> Sheet
    @State private var coverShown = false
    @Environment(\.locale) private var locale
    @Environment(\.shooReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .onAppear { if isPresented { show(true) } }
            .onChange(of: isPresented) { _, now in if now { show(true) } }
            .fullScreenCover(isPresented: $coverShown, onDismiss: {
                if isPresented { isPresented = false }
                onDismiss?()
            }) {
                PeekSheetHost(isPresented: $isPresented, background: background, removeCover: { show(false) }, content: sheet)
                    .presentationBackground(.clear)
                    // As ShooDialog does: the app's language and motion setting reach into the cover.
                    .environment(\.locale, locale)
                    .environment(\.shooReduceMotion, reduceMotion)
            }
    }

    /// The cover itself appears and goes without its slide: the host animates the dimming and the card.
    private func show(_ shown: Bool) {
        guard coverShown != shown else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { coverShown = shown }
    }
}

private struct PeekSheetHost<Content: View>: View {
    @Binding var isPresented: Bool
    let background: Color
    let removeCover: () -> Void
    @ViewBuilder let content: () -> Content
    @Environment(\.shooReduceMotion) private var reduceMotion
    @State private var shown = false
    @State private var closing = false
    @State private var drag: CGFloat = 0
    @State private var dismissDisabled = false

    /// Pulled down this far (or flicked), the sheet closes; less, it springs back.
    static var closeDistance: CGFloat { 110 }

    private var motion: Animation { reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.38, bounce: 0.12) }

    var body: some View {
        ZStack(alignment: .bottom) {
            // The system sheet's dimming.
            Color.black.opacity(shown ? 0.22 : 0)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { close() }
                .accessibilityHidden(true)
            if shown {
                PeekSheetChrome(background: background, content: content)
                    .offset(y: drag)
                    .gesture(dragToClose)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom))
                    .accessibilityAddTraits(.isModal)
                    .onPreferenceChange(PeekSheetDismissDisabledKey.self) { dismissDisabled = $0 }
            }
        }
        .environment(\.closePeekSheet, { close(force: true) })
        .accessibilityAction(.escape) { close() }
        .onAppear { withAnimation(motion) { shown = true } }
        // The presenter set its binding to false (e.g. a done flow): slide down too.
        .onChange(of: isPresented) { _, now in if !now { close(force: true) } }
    }

    private var dragToClose: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                // Down follows the finger (a little only while closing is off); up gives a little, as a sheet does.
                let dy = value.translation.height
                drag = dy > 0 && !dismissDisabled ? dy : dy / 6
            }
            .onEnded { value in
                if value.translation.height > Self.closeDistance || value.predictedEndTranslation.height > Self.closeDistance * 2.5 {
                    close()
                } else {
                    withAnimation(motion) { drag = 0 }
                }
            }
    }

    private func close(force: Bool = false) {
        guard !closing else { return }
        guard force || !dismissDisabled else {
            withAnimation(motion) { drag = 0 }
            return
        }
        closing = true
        withAnimation(motion) {
            shown = false
        } completion: {
            removeCover()
            if isPresented { isPresented = false }
        }
    }
}

/// The card and the mascot. The body is drawn first (behind the card), the fingers last (in front of it).
struct PeekSheetChrome<Content: View>: View {
    var cornerRadius: CGFloat = 32
    var background: Color = .white
    @ViewBuilder var content: () -> Content
    @Environment(\.closePeekSheet) private var close
    @Environment(\.shooReduceMotion) private var reduceMotion
    @State private var peeks = false

    /// Figma: the peek pose 147 x 104, its right edge 56 pt in from the screen's.
    static var poseHeight: CGFloat { 104 }
    static var poseWidth: CGFloat { poseHeight * Mascot.peek.aspectRatio }
    static var trailingInset: CGFloat { 56 }
    /// How far the body rises above the card: the source row where the edge cuts it (97 pt of 104).
    static var rise: CGFloat { (poseHeight * Mascot.peekEdgeFraction).rounded() }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            pose(Mascot.peek.image)
            VStack(spacing: 0) {
                // Beside the mascot, above the card, the dimming shows through: a tap there closes, as on the dimming.
                Color.clear
                    .frame(height: Self.rise)
                    .contentShape(Rectangle())
                    .onTapGesture { close() }
                    .accessibilityHidden(true)
                content()
                    .frame(maxWidth: .infinity)
                    .background(alignment: .top) {
                        UnevenRoundedRectangle(topLeadingRadius: cornerRadius, topTrailingRadius: cornerRadius, style: .continuous)
                            .fill(background)
                            .ignoresSafeArea(edges: .bottom)
                    }
            }
            pose(Image(Mascot.peekHandsAssetName))
                .shadow(color: .black.opacity(peeks ? 0.14 : 0), radius: 1.5, y: 1)
        }
        .onAppear {
            // Shoo climbs up once the card is in; with Reduce Motion it only fades in.
            withAnimation(reduceMotion ? .easeOut(duration: 0.2).delay(0.15) : .spring(duration: 0.45, bounce: 0.3).delay(0.3)) {
                peeks = true
            }
        }
    }

    private func pose(_ image: Image) -> some View {
        image
            .resizable()
            .scaledToFit()
            .frame(width: Self.poseWidth, height: Self.poseHeight)
            .padding(.trailing, Self.trailingInset)
            .offset(y: peeks || reduceMotion ? 0 : Self.rise * 0.7)
            .opacity(peeks ? 1 : 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

#Preview {
    Color.gray.peekSheet(isPresented: .constant(true)) {
        Text(verbatim: "Sheet").frame(maxWidth: .infinity, minHeight: 300)
    }
}
