import SwiftUI

/// Figma "Shield Kaca Halftone" (Activity empty states, node 480:5502): a glass shield over a blue core
/// with a halftone dot pattern. On: the glow breathes, a light wave runs up the dots and a shine sweeps
/// the glass. Off ("Perlindungan sedang mati", node 480:5592): grey with a power symbol in the dots, still.
/// Reduce Motion keeps the On look without movement.
struct HalftoneShield: View {
    var isOn = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Figma "Ilustrasi": 220 × 176; the 184 × 201 shield frame sits at (18, −13) and overflows it.
    static let size = CGSize(width: 220, height: 176)

    var body: some View {
        TimelineView(.animation(paused: !isOn || reduceMotion)) { context in
            let time = isOn && !reduceMotion ? context.date.timeIntervalSinceReferenceDate : nil
            ShieldLayers(palette: isOn ? .on : .off, time: time)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .accessibilityHidden(true)
    }
}

// MARK: Layers

private struct ShieldLayers: View {
    let palette: ShieldPalette
    /// nil = still picture.
    let time: TimeInterval?

    /// 0…1, slow breath of the glow (2.4 s in, 2.4 s out).
    private var breath: Double {
        guard let time else { return 0.5 }
        return (1 - cos(time * .pi / 2.4)) / 2
    }

    var body: some View {
        let glass = GlassShieldShape()
        ZStack(alignment: .topLeading) {
            // Glow: 114 × 109 ellipse, 10 % fill, 40 blur.
            Ellipse()
                .fill(palette.glow.opacity(0.1 + 0.06 * breath))
                .frame(width: 114.4, height: 109.2)
                .scaleEffect(0.96 + 0.08 * breath)
                .blur(radius: 20)
                .position(x: 35 + 57.2, y: 61 + 54.6)

            // Kaca shadow: the big soft glow under the glass (y 16, blur 30, 35 %). Drawn as its own
            // blurred shape: Figma casts it from the shape, SwiftUI's `.shadow` from the nearly clear fill.
            glass
                .fill(palette.glow.opacity(0.27 + 0.16 * breath))
                .frame(width: 104, height: 121.33)
                .blur(radius: 15 + 4 * breath)
                .position(x: 40 + 52, y: 40 + 60.67 + 16)

            // Core: 85 × 99, gradient, 1 pt stroke, two inner shadows.
            glass
                .fill(
                    LinearGradient(colors: [palette.coreTop, palette.coreBottom], startPoint: .top, endPoint: .bottom)
                        .shadow(.inner(color: .white.opacity(0.55), radius: 4, y: 4))
                        .shadow(.inner(color: palette.glow.opacity(0.45), radius: 7, y: -6))
                )
                .overlay(glass.stroke(palette.coreStroke.opacity(0.9), lineWidth: 1))
                .frame(width: 85.28, height: 99.49)
                .position(x: 49 + 42.64, y: 55 + 49.75)

            HalftoneDots(rows: palette.dots, glow: palette.glow, time: time)
                .frame(width: 70.7, height: 86.8)
                .position(x: 49 + 7 + 35.35, y: 55 + 5 + 43.4)

            // Kaca: 104 × 121 glass with a 2 pt gradient stroke and a small inner light.
            glass
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.42), location: 0),
                            .init(color: .white.opacity(0.12), location: 0.45),
                            .init(color: .white.opacity(0.22), location: 1),
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    .shadow(.inner(color: .white.opacity(0.5), radius: 1.5, y: 2))
                )
                .overlay(
                    glass.stroke(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.95), location: 0),
                                .init(color: .white.opacity(0.25), location: 0.5),
                                .init(color: .white.opacity(0.7), location: 1),
                            ],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
                )
                .overlay(GlassSweep(time: time).clipShape(glass))
                .frame(width: 104, height: 121.33)
                .position(x: 40 + 52, y: 40 + 60.67)

            // Kilau: 44 × 19 white highlight, 55 %, blur 8.
            Ellipse()
                .fill(.white.opacity(0.55))
                .frame(width: 43.68, height: 19.41)
                .blur(radius: 4)
                .position(x: 55 + 21.84, y: 57 + 9.7)
        }
        .frame(width: 184, height: 201.33, alignment: .topLeading)
        .offset(x: 18, y: -13)
        .frame(width: HalftoneShield.size.width, height: HalftoneShield.size.height, alignment: .topLeading)
    }
}

/// A light streak that crosses the glass every 5 s (0.9 s pass, then rest).
private struct GlassSweep: View {
    let time: TimeInterval?

    var body: some View {
        GeometryReader { proxy in
            if let time {
                let period = 5.0, pass = 0.9
                let phase = time.truncatingRemainder(dividingBy: period) / pass
                if phase < 1 {
                    let width = proxy.size.width
                    LinearGradient(
                        colors: [.white.opacity(0), .white.opacity(0.45), .white.opacity(0)],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: width * 0.45, height: proxy.size.height * 1.6)
                    .rotationEffect(.degrees(20))
                    .offset(x: -width * 0.6 + phase * width * 1.7, y: -proxy.size.height * 0.3)
                    .blendMode(.plusLighter)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: Dots

/// "Titik halftone": 335 dots on a 3.89 pt grid, radii from Figma. White → #D7F6FF top to bottom,
/// with the two Figma drop shadows. While moving, a soft wave of light runs from bottom to top.
private struct HalftoneDots: View {
    let rows: [[CGFloat]]
    let glow: Color
    let time: TimeInterval?

    private static let pitch: CGFloat = 3.8875
    private static let origin = CGPoint(x: 0.45, y: 0.35)

    /// White at the top to #D7F6FF at the bottom (`Color.mix` needs iOS 18).
    private static func shade(at fraction: Double) -> Color {
        let f = min(max(fraction, 0), 1)
        return Color(red: 1 - f * (1 - 0xD7 / 255), green: 1 - f * (1 - 0xF6 / 255), blue: 1)
    }

    var body: some View {
        Canvas { context, size in
            let height = CGFloat(rows.count - 1) * Self.pitch
            // Wave centre runs from below the dots to above them in 2.6 s, then rests 1.4 s.
            var waveY: CGFloat?
            if let time {
                let t = time.truncatingRemainder(dividingBy: 4.0) / 2.6
                if t < 1 { waveY = height + 12 - CGFloat(t) * (height + 24) }
            }
            context.addFilter(.shadow(color: glow.opacity(0.5), radius: 0.75, x: 0, y: 1))
            context.addFilter(.shadow(color: .white.opacity(0.45), radius: 1.25))
            for (row, radii) in rows.enumerated() {
                let y = Self.origin.y + CGFloat(row) * Self.pitch
                let shade = Self.shade(at: Double(y / max(height, 1)))
                var boost: CGFloat = 0
                if let waveY {
                    let distance = (y - waveY) / 9
                    boost = exp(-distance * distance)
                }
                for (column, radius) in radii.enumerated() where radius > 0 {
                    let x = Self.origin.x + CGFloat(column) * Self.pitch
                    let r = radius * (1 + 0.35 * boost)
                    let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(shade.opacity(0.85 + 0.15 * boost)))
                }
            }
        }
    }
}

// MARK: Shape and colours

/// Outline of the glass and the core (same proportions), traced from the Figma vector (104 × 121.33).
struct GlassShieldShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width / 104, h = rect.height / 121.33
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * w, y: rect.minY + y * h) }
        var path = Path()
        path.move(to: p(52, 0))
        path.addCurve(to: p(104, 15.89), control1: p(66.44, 8.67), control2: p(83.78, 14.44))
        path.addLine(to: p(104, 57.78))
        path.addCurve(to: p(52, 121.33), control1: p(104, 89.56), control2: p(80.89, 111.22))
        path.addCurve(to: p(0, 57.78), control1: p(23.11, 111.22), control2: p(0, 89.56))
        path.addLine(to: p(0, 15.89))
        path.addCurve(to: p(52, 0), control1: p(20.22, 14.44), control2: p(37.56, 8.67))
        path.closeSubpath()
        return path
    }
}

private struct ShieldPalette {
    let glow: Color
    let coreTop: Color
    let coreBottom: Color
    let coreStroke: Color
    let dots: [[CGFloat]]

    static let on = ShieldPalette(
        glow: ActivityStyle.hex(0x1A73D9), coreTop: ActivityStyle.hex(0x4FB4F2),
        coreBottom: ActivityStyle.hex(0x0F55B0), coreStroke: ActivityStyle.hex(0x1E6CB0),
        dots: decode(onDots)
    )
    static let off = ShieldPalette(
        glow: ActivityStyle.hex(0x54667D), coreTop: ActivityStyle.hex(0xB4BFCC),
        coreBottom: ActivityStyle.hex(0x56677B), coreStroke: ActivityStyle.hex(0x55677D),
        dots: decode(offDots)
    )

    /// Rows split by "|", radii in 1/100 pt split by ",", 0 = no dot.
    private static func decode(_ text: String) -> [[CGFloat]] {
        text.split(separator: "|").map { row in
            row.split(separator: ",").map { CGFloat(Int($0) ?? 0) / 100 }
        }
    }

    /// Figma 480:5506 (shield "on", a person in the dots).
    private static let onDots = """
    0,0,0,0,0,0,0,0,0,35,0,0,0,0,0,0,0,0,0|0,0,0,0,0,0,0,40,37,38,40,40,0,0,0,0,0,0,0|\
    0,0,0,0,0,40,40,40,42,45,40,40,40,38,0,0,0,0,0|35,35,38,38,40,45,43,45,45,50,45,45,45,45,40,37,35,35,32|\
    35,35,40,40,45,45,47,78,105,112,102,78,45,45,45,40,40,35,35|38,40,40,43,47,47,80,120,135,138,135,120,78,47,48,40,40,37,37|\
    37,40,42,45,47,50,105,137,140,140,140,137,105,53,50,47,45,43,40|35,45,47,47,55,55,115,142,145,145,142,142,115,55,53,47,45,45,37|\
    43,45,47,50,55,55,108,140,145,145,145,140,105,55,55,50,45,45,40|42,48,50,50,58,60,80,127,145,147,145,130,80,58,57,50,50,48,40|\
    42,45,50,52,55,60,62,80,110,122,110,80,65,60,55,52,50,45,42|45,45,50,55,55,62,65,67,75,75,73,67,65,65,55,52,50,45,45|\
    45,45,50,55,55,60,65,67,73,75,70,67,65,63,55,53,50,45,45|42,48,50,50,58,60,60,68,68,70,70,70,63,60,57,50,50,48,42|\
    42,45,50,50,55,58,70,80,90,92,90,80,70,58,55,50,50,45,40|0,45,48,50,65,85,102,115,120,125,120,115,105,85,65,50,45,45,0|\
    0,42,45,67,95,112,125,133,135,135,138,133,125,115,92,67,45,45,0|0,0,60,90,110,125,135,140,140,140,140,140,135,125,110,90,60,0,0|\
    0,0,0,100,120,130,135,135,138,138,138,138,135,132,120,100,0,0,0|0,0,0,0,125,130,133,133,135,135,135,133,135,130,123,0,0,0,0|\
    0,0,0,0,0,125,130,130,130,130,130,130,130,125,0,0,0,0,0|0,0,0,0,0,0,128,130,127,127,130,130,125,0,0,0,0,0,0|\
    0,0,0,0,0,0,0,0,123,125,123,0,0,0,0,0,0,0,0
    """

    /// Figma 480:5596 (shield "off", a power symbol in the dots).
    private static let offDots = """
    0,0,0,0,0,0,0,0,0,35,0,0,0,0,0,0,0,0,0|0,0,0,0,0,0,0,40,37,38,40,40,0,0,0,0,0,0,0|\
    0,0,0,0,0,40,40,40,42,45,40,40,40,38,0,0,0,0,0|35,35,38,38,40,45,43,45,45,45,45,45,45,45,40,37,35,35,32|\
    35,35,40,40,45,45,47,50,47,47,50,50,45,45,45,40,40,35,35|38,40,40,43,47,47,50,50,53,88,50,50,50,47,48,40,40,37,37|\
    37,40,42,45,47,85,125,55,85,130,85,55,125,85,50,47,45,43,40|35,45,47,47,105,138,143,58,115,145,118,58,143,135,108,47,45,45,37|\
    43,45,47,105,138,140,143,60,135,145,135,60,145,142,140,108,45,45,40|42,48,80,137,140,142,145,63,143,147,143,63,145,142,140,140,80,48,40|\
    42,45,120,140,142,145,115,67,145,153,145,67,115,145,140,140,120,45,42|45,55,133,138,145,135,65,67,135,155,138,67,65,135,143,138,135,55,45|\
    45,70,138,140,142,105,65,67,115,153,113,67,65,105,140,140,135,73,45|42,77,135,140,140,97,60,68,70,123,70,70,63,97,140,140,135,77,42|\
    42,67,133,140,140,110,60,63,65,67,65,63,60,113,140,140,135,68,40|0,45,127,135,135,135,57,60,65,65,63,60,57,135,138,138,127,45,0|\
    0,42,108,135,135,135,122,60,55,55,58,60,125,135,135,133,107,45,0|0,0,60,130,135,135,140,135,118,108,120,135,137,135,135,130,60,0,0|\
    0,0,0,88,130,132,135,135,138,138,138,138,135,132,130,90,0,0,0|0,0,0,0,85,125,133,133,135,135,135,133,135,125,85,0,0,0,0|\
    0,0,0,0,0,55,102,122,127,130,127,122,102,55,0,0,0,0,0|0,0,0,0,0,0,40,40,55,63,55,40,40,0,0,0,0,0,0|\
    0,0,0,0,0,0,0,0,38,38,40,0,0,0,0,0,0,0,0
    """
}

#Preview {
    VStack(spacing: 40) {
        HalftoneShield()
        HalftoneShield(isOn: false)
    }
    .padding()
    .background(ActivityStyle.background)
}
