import SwiftUI

/// Figma "Scam Score Gauge" (Detail score card, 416:9268 / 416:9481): a 205° band with a halo, the score
/// filled in red (blocked) or orange (warning), white dots on the fill, nine ticks, a needle at the tip,
/// the percentage and the label ("Bahaya" / "Risiko Tinggi"). Values are the Figma ones; the frame is
/// 370 × 237 pt and scales down with the card on narrower screens.
struct ScoreGauge: View {
    let score: Int
    let status: ScanStatus

    @Environment(\.locale) private var locale
    private var language: AppLanguage { AppLanguage(locale: locale) }

    static let size = CGSize(width: 370, height: 237)
    /// Centre and radii of the band (Track 298 pt at 36, 28; Halo 316 pt).
    private static let center = CGPoint(x: 185, y: 177)
    private static let outer: CGFloat = 149
    private static let inner: CGFloat = 100
    private static let haloOuter: CGFloat = 158
    /// The band runs 167.4° → 372.6° (clockwise from 3 o'clock); the score maps 0–100 onto 180° → 360°.
    private static let bandStart = 167.4
    private static let bandEnd = 372.6

    /// Fill tip: 180° + 1.8° per point (Figma: 92 → 345.6°, 72 → 309.6°).
    static func tipAngle(score: Int) -> Double { 180 + Double(min(max(score, 0), 100)) * 1.8 }

    private var palette: GaugePalette { status == .blocked ? .red : .orange }

    var body: some View {
        let palette = palette
        let tip = Self.tipAngle(score: score)
        ZStack(alignment: .topLeading) {
            // Halo: 9 pt rim outside the band, blur 3.
            BandShape(center: Self.center, inner: Self.outer, outer: Self.haloOuter, from: Self.bandStart, to: Self.bandEnd)
                .fill(palette.halo)
                .blur(radius: 1.5)
                .mask(Self.fade(top: 19, height: 316, strength: 1))
            // Track.
            BandShape(center: Self.center, inner: Self.inner, outer: Self.outer, from: Self.bandStart, to: Self.bandEnd)
                .fill(Self.radial(palette.track, locations: [0.67, 1]))
                .mask(Self.fade(top: 28, height: 298, strength: 1))
            // Progress, with its inner light, inner shade and coloured drop shadow.
            BandShape(center: Self.center, inner: Self.inner, outer: Self.outer, from: Self.bandStart, to: tip)
                .fill(
                    Self.radial(palette.progress, locations: [0.68, 0.76, 0.86, 0.95, 1])
                        .shadow(.inner(color: .white.opacity(0.45), radius: 4.25, x: -4.3, y: -4.3))
                        .shadow(.inner(color: palette.innerShade.opacity(0.35), radius: 5.3, x: 4.3, y: 6.4))
                )
                .shadow(color: palette.glow.opacity(0.25), radius: 10.65, y: 8.5)
                .mask(Self.fade(top: 28, height: 298, strength: 0.45))
            dots(tip: tip)
            ticks
            needle(at: tip)
            VStack(spacing: 0) {
                Text(verbatim: Formatters.percent(score, language: language))
                    .activityFont(48, tracking: -0.48)
                    .frame(height: 57)
                    .padding(.top, 116)
                Text(status == .blocked ? "Danger" : "detail.highRisk")
                    .activityFont(20, .medium, tracking: -0.1)
                    .padding(.top, 7)
            }
            .foregroundStyle(DetailStyle.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: Self.size.width)
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
    }

    // MARK: Pieces

    /// White dots on the fill (Figma "Dots strong" 95 %, "Dots soft" 55 %), only where the fill reaches.
    private func dots(tip: Double) -> some View {
        Canvas { context, _ in
            for (dots, opacity) in [(Self.strongDots, 0.95), (Self.softDots, 0.55)] {
                for dot in dots where Self.angle(of: dot) <= tip - 6 {
                    let rect = CGRect(x: dot.x - 1.2, y: dot.y - 1.2, width: 2.4, height: 2.4)
                    context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(opacity)))
                }
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .allowsHitTesting(false)
    }

    /// Nine ticks every 22.5° from 180° to 360°, 7 × 1.8 pt between r 105 and 112.
    private var ticks: some View {
        Canvas { context, _ in
            let opacities = [0.18, 0.34, 0.48, 0.57, 0.6, 0.57, 0.48, 0.34, 0.18]
            for (index, opacity) in opacities.enumerated() {
                let angle = 180 + Double(index) * 22.5
                let path = Self.radialBar(angle: angle, from: 105, to: 112, thickness: 1.8)
                context.fill(path, with: .color(DetailStyle.tick.opacity(opacity)))
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .allowsHitTesting(false)
    }

    /// 24 × 3 pt needle across the inner edge (r 99 → 123), at the fill's tip.
    private func needle(at angle: Double) -> some View {
        Canvas { context, _ in
            context.fill(Self.radialBar(angle: angle, from: 99, to: 123, thickness: 3), with: .color(DetailStyle.needle))
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .allowsHitTesting(false)
    }

    // MARK: Geometry

    private static func point(angle: Double, radius: CGFloat) -> CGPoint {
        let radians = angle * .pi / 180
        return CGPoint(x: center.x + radius * cos(radians), y: center.y + radius * sin(radians))
    }

    private static func angle(of point: CGPoint) -> Double {
        let degrees = atan2(point.y - center.y, point.x - center.x) * 180 / .pi
        return degrees < 90 ? degrees + 360 : degrees
    }

    private static func radialBar(angle: Double, from: CGFloat, to: CGFloat, thickness: CGFloat) -> Path {
        let radians = angle * .pi / 180
        let start = point(angle: angle, radius: from)
        let length = to - from
        let rect = CGRect(x: 0, y: -thickness / 2, width: length, height: thickness)
        let transform = CGAffineTransform(translationX: start.x, y: start.y).rotated(by: radians)
        return Path(roundedRect: rect, cornerRadius: thickness / 2).applying(transform)
    }

    private static func radial(_ colors: [Color], locations: [CGFloat]) -> RadialGradient {
        RadialGradient(
            stops: zip(colors, locations).map { Gradient.Stop(color: $0, location: $1) },
            center: UnitPoint(x: center.x / size.width, y: center.y / size.height),
            startRadius: 0, endRadius: outer
        )
    }

    /// Figma lays a white top-to-bottom gradient over each ellipse so the band's ends fade into the card
    /// (stops 0 / 0.26 clear, 0.45 at 55 %, 0.56 opaque). As a mask it works on any card colour.
    private static func fade(top: CGFloat, height: CGFloat, strength: Double) -> some View {
        let start = top / size.height, span = height / size.height
        return LinearGradient(
            stops: [
                .init(color: .black, location: start + 0.26 * span),
                .init(color: .black.opacity(1 - 0.55 * strength), location: start + 0.45 * span),
                .init(color: .black.opacity(1 - strength), location: start + 0.56 * span),
            ],
            startPoint: .top, endPoint: .bottom
        )
    }

    /// Figma "Dots strong" / "Dots soft" of the 92 % gauge (centres, r 1.2); a lower score shows fewer.
    private static let strongDots: [CGPoint] = [
        (231, 53), (246, 53), (126, 68), (141, 68), (186, 68), (216, 68), (231, 68), (261, 83), (96, 98), (276, 98), (306, 113),
    ].map { CGPoint(x: $0.0, y: $0.1) }
    private static let softDots: [CGPoint] = [
        (126, 53), (141, 53), (156, 53), (171, 53), (186, 53), (201, 53), (216, 53), (111, 68), (246, 68), (261, 68),
        (126, 83), (111, 98), (261, 98), (291, 98), (66, 113), (276, 113),
    ].map { CGPoint(x: $0.0, y: $0.1) }
}

/// A ring segment between two radii, `from` → `to` degrees clockwise from 3 o'clock.
private struct BandShape: Shape {
    let center: CGPoint
    let inner: CGFloat
    let outer: CGFloat
    let from: Double
    let to: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard to > from else { return path }
        path.addArc(center: center, radius: outer, startAngle: .degrees(from), endAngle: .degrees(to), clockwise: false)
        path.addArc(center: center, radius: inner, startAngle: .degrees(to), endAngle: .degrees(from), clockwise: true)
        path.closeSubpath()
        return path
    }
}

private struct GaugePalette {
    let halo: Color
    let track: [Color]
    let progress: [Color]
    let innerShade: Color
    let glow: Color

    static let red = GaugePalette(
        halo: DetailStyle.hex(0xFBE5E4),
        track: [DetailStyle.hex(0xF9D9D6), DetailStyle.hex(0xFDEEEC)],
        progress: [0xC42B1C, 0xE5483B, 0xFF7A6B, 0xE5483B, 0xBF3424].map(DetailStyle.hex),
        innerShade: DetailStyle.hex(0x8A1C12),
        glow: DetailStyle.hex(0xE5473B)
    )
    static let orange = GaugePalette(
        halo: DetailStyle.hex(0xFFF0DB),
        track: [DetailStyle.hex(0xFFE6C4), DetailStyle.hex(0xFFF4E3)],
        progress: [0xEB8900, 0xFF9500, 0xFFB752, 0xFF9500, 0xE58600].map(DetailStyle.hex),
        innerShade: DetailStyle.hex(0xA66100),
        glow: DetailStyle.hex(0xFF9400)
    )
}

#Preview {
    VStack {
        ScoreGauge(score: 92, status: .blocked)
        ScoreGauge(score: 72, status: .warning)
    }
}
