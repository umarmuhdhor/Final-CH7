import SwiftUI

/// Three soft discs that grow and fade one after the other (`period` for each, so a new one every third of it).
/// Reduce Motion keeps them still.
struct SoftPulse: View {
    var color: Color = .white
    let smallest: CGFloat
    let largest: CGFloat
    let peak: Double
    /// One disc's life in seconds.
    var period: Double = 4

    @Environment(\.shooReduceMotion) private var reduceMotion

    /// A disc fades in over this share of its life, so it never pops up behind the glass.
    private static let fadeIn = 0.12

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let time = reduceMotion ? period * 0.15 : context.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    let phase = (time / period + Double(index) / 3).truncatingRemainder(dividingBy: 1)
                    Circle()
                        .fill(color.opacity(peak * min(phase / Self.fadeIn, 1) * pow(1 - phase, 1.2)))
                        .frame(width: smallest + phase * (largest - smallest), height: smallest + phase * (largest - smallest))
                }
            }
        }
        .frame(width: largest, height: largest)
        .accessibilityHidden(true)
    }
}

/// Loading state for a whole area: a small `HalftoneShield` on the pulse of the Home hero.
/// Screens with the big shield already in view keep the plain spinner.
struct ShieldPulseLoader: View {
    private static let shieldScale: CGFloat = 0.46

    var body: some View {
        ZStack {
            SoftPulse(color: ActivityStyle.hex(0x1A73D9), smallest: 50, largest: 180, peak: 0.22)
            HalftoneShield()
                .scaleEffect(Self.shieldScale)
                .frame(width: HalftoneShield.size.width * Self.shieldScale,
                       height: HalftoneShield.size.height * Self.shieldScale)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Loading"))
    }
}

#Preview {
    ShieldPulseLoader()
        .padding()
        .background(ActivityStyle.background)
}
