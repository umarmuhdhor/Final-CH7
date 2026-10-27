import SwiftUI

/// Outline of the Guardian Home shield (Figma "Guardian/Home" › Union, 140 × 153 pt), traced from the vector.
struct ShieldShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * w, y: rect.minY + y * h) }
        var path = Path()
        path.move(to: p(0.5, 0))
        path.addCurve(to: p(1, 0.22), control1: p(0.66, 0.015), control2: p(0.985, 0.09))
        path.addLine(to: p(1, 0.53))
        path.addCurve(to: p(0.56, 0.985), control1: p(1, 0.76), control2: p(0.74, 0.9))
        path.addQuadCurve(to: p(0.44, 0.985), control: p(0.5, 1.015))
        path.addCurve(to: p(0, 0.53), control1: p(0.26, 0.9), control2: p(0, 0.76))
        path.addLine(to: p(0, 0.22))
        path.addCurve(to: p(0.5, 0), control1: p(0.015, 0.09), control2: p(0.34, 0.015))
        path.closeSubpath()
        return path
    }
}

/// The Home hero shield. Active: cyan with a soft glow that breathes slowly. Off: dimmed, no glow.
/// Reduce Motion keeps the glow but stops the breathing.
struct GlowingShield: View {
    var isActive = true
    var width: CGFloat = 140

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    private static let glow = Color(red: 0x8F / 255, green: 0xE9 / 255, blue: 0xEC / 255)
    private static let top = Color(red: 0xA9 / 255, green: 0xF4 / 255, blue: 0xF1 / 255)
    private static let bottom = Color(red: 0x7F / 255, green: 0xD9 / 255, blue: 0xF0 / 255)

    /// 0 → 1 over one breath; fixed in the middle when nothing moves.
    private var phase: CGFloat { reduceMotion ? 0.5 : (breathing ? 1 : 0) }

    var body: some View {
        let shape = ShieldShape()
        ZStack {
            if isActive {
                // Wide halo, then a tighter one: the glow fades out instead of ending in a ring.
                shape.fill(Self.glow)
                    .blur(radius: 26 + 10 * phase)
                    .opacity(0.45 + 0.35 * phase)
                    .scaleEffect(1.04 + 0.06 * phase)
                shape.fill(Self.glow)
                    .blur(radius: 9)
                    .opacity(0.55 + 0.25 * phase)
            }
            shape
                .fill(LinearGradient(colors: [Self.top, Self.bottom], startPoint: .top, endPoint: .bottom))
                // Soft light from inside, like the Figma "Purple Sky" mask.
                .overlay(
                    shape.fill(RadialGradient(colors: [.white.opacity(0.55), .clear],
                                              center: UnitPoint(x: 0.5, y: 0.35), startRadius: 0, endRadius: width * 0.55))
                )
                .overlay(shape.stroke(.white.opacity(0.7), lineWidth: 1.5).blur(radius: 2))
                .clipShape(shape)
                .saturation(isActive ? 1 : 0.15)
                .opacity(isActive ? 1 : 0.6)
        }
        .frame(width: width, height: width * 153 / 140)
        .accessibilityHidden(true)
        .onAppear { startBreathing() }
        .onChange(of: reduceMotion) { _, _ in startBreathing() }
    }

    private func startBreathing() {
        guard !reduceMotion else {
            breathing = false
            return
        }
        breathing = false
        withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
            breathing = true
        }
    }
}

#Preview {
    HStack(spacing: 40) {
        GlowingShield()
        GlowingShield(isActive: false)
    }
    .padding(60)
    .background(LinearGradient(colors: [Color(red: 0.12, green: 0.47, blue: 0.75), Color(red: 0.41, green: 0.8, blue: 0.98)],
                               startPoint: .topLeading, endPoint: .bottomTrailing))
}
