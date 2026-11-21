import SwiftUI

/// Figma "alief notif" section 2 (2431:12760, fase 29g): a toast as a gradient card in its own colour with Shoo peeking
/// over the card's left edge. Placed like an iOS notification: 16 pt from the edges, Shoo's head 8 pt under the status
/// bar (the caller adds the 8). The title with at most two lines under it, and an optional small button on the right.
/// Slides in from the top and leaves upwards (the caller's transition); closes by itself after `duration`, with a tap,
/// swiped up, or with Escape; VoiceOver reads it once. Home's role and pairing toasts (`HomeNoticeToast`) and ON-04's
/// "back from Settings" status (F3) use it.
struct ShooToast<Accessory: View>: View {
    let title: String
    let line: String
    /// Light on the left, dark on the right.
    let colors: [Color]
    let pose: Mascot
    /// `home.notice` → `home.notice` on the card, `home.notice.text` on the title and line.
    let identifier: String
    /// Already longer for VoiceOver where the caller wants that (WCAG 2.2.1).
    var duration: Duration = .seconds(4)
    /// Screenshots only: stays until tapped.
    var staysOpen = false
    let onClose: () -> Void
    @ViewBuilder var accessory: () -> Accessory

    @Environment(\.shooReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var drag: CGFloat = 0

    /// Figma (Home toasts drawn at 2x): Shoo 86 pt tall, 8 pt in from the card's left edge, 22 pt over its top; the text
    /// starts at 96, or 6 pt after a wider pose (Tidur, 113 in F3).
    static var mascotHeight: CGFloat { 86 }
    static var mascotOverhang: CGFloat { 22 }
    private static var mascotInset: CGFloat { 8 }

    private var textInset: CGFloat {
        let width = Self.mascotHeight * pose.aspectRatio
        // Standing poses fit in Figma's 88 pt slot; a wide one (Tidur) pushes the text 6 pt past its right edge.
        return width <= 90 ? 96 : Self.mascotInset + width + 6
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .onboardingFont(16, weight: .semibold, relativeTo: .headline)
                    .foregroundStyle(.white)
                Text(verbatim: line)
                    .onboardingFont(13, relativeTo: .subheadline)
                    .foregroundStyle(.white.opacity(0.92))
                    // Two lines keep the banner short; larger text sizes may wrap further (VoiceOver reads it all).
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("\(identifier).text")
            accessory()
        }
        .padding(.leading, textInset)
        .padding(.trailing, 12)
        .padding(.vertical, 16)
        .frame(minHeight: 85)
        .background(
            LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        // Figma: #0D1A33 at 18 %, blur 24, 8 down.
        .shadow(color: Color(hex: 0x0D1A33, opacity: 0.18), radius: 12, y: 8)
        // Shoo stands on the card's left part and peeks over its top edge.
        .overlay(alignment: .topLeading) {
            MascotImage(pose: pose, height: Self.mascotHeight)
                .offset(x: Self.mascotInset, y: -Self.mascotOverhang)
        }
        .padding(.top, Self.mascotOverhang)
        .environment(\.colorScheme, .light)
        .padding(.horizontal, 16)
        .offset(y: min(drag, 0))
        .contentShape(Rectangle())
        .onTapGesture(perform: onClose)
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { drag = $0.translation.height }
                .onEnded { value in
                    if value.translation.height < -24 { onClose() }
                    withAnimation(reduceMotion ? nil : .snappy) { drag = 0 }
                }
        )
        .accessibilityElement(children: .contain)
        .accessibilityAction(.escape, onClose)
        .accessibilityIdentifier(identifier)
        .task {
            AccessibilityNotification.Announcement("\(title). \(line)").post()
            guard !staysOpen else { return }
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            onClose()
        }
    }
}

extension ShooToast where Accessory == EmptyView {
    init(
        title: String, line: String, colors: [Color], pose: Mascot, identifier: String,
        duration: Duration = .seconds(4), staysOpen: Bool = false, onClose: @escaping () -> Void
    ) {
        self.init(
            title: title, line: line, colors: colors, pose: pose, identifier: identifier,
            duration: duration, staysOpen: staysOpen, onClose: onClose, accessory: { EmptyView() }
        )
    }
}

#Preview {
    ZStack(alignment: .top) {
        Color(.systemGroupedBackground).ignoresSafeArea()
        ShooToast(
            title: "Shoo isn't on yet", line: "Open Settings again and switch Shoo on (step 02).",
            colors: [Color(hex: 0xF2B14C), Color(hex: 0xE0892B)], pose: .sleep, identifier: "preview", staysOpen: true,
            onClose: {}
        )
        .padding(.top, 8)
    }
}
