import SwiftUI

/// ON-01 logo in motion, after the Rive "Shoo Bird" state machine with its Look layer off: the shield
/// breathes, the bird blinks twice and the sparkle twinkles. The first blink and twinkle come early so they
/// land inside the 1.9 s splash; after that they loop like the Rive layers. Reduce Motion keeps the still logo.
struct ShooBirdLogo: View {
    @Environment(\.shooReduceMotion) private var reduceMotion
    @State private var start = Date()

    /// `ShooLogo` is 408 × 456 px at @3x.
    static let size = CGSize(width: 136, height: 152)

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let time = reduceMotion ? 0 : context.date.timeIntervalSince(start)
            let twinkle = Self.twinkle(at: time)
            Image("ShooLogo")
                .overlay {
                    ZStack {
                        EyeSlit(points: EyeSlit.left).fill(Color(hex: 0x212121))
                        EyeSlit(points: EyeSlit.right).fill(Color(hex: 0x48505B))
                    }
                    .opacity(Self.blink(at: time))
                }
                .overlay(alignment: .topLeading) {
                    // Where the app icon has its sparkle, on the top right of the shield rim.
                    SparkleStar()
                        .fill(.white)
                        .shadow(color: .white.opacity(0.8), radius: 4)
                        .frame(width: 30, height: 28)
                        .scaleEffect(0.75 + 0.4 * twinkle)
                        .rotationEffect(.degrees(45 * twinkle))
                        .opacity(0.8 + 0.2 * twinkle)
                        .position(x: 129, y: 30)
                }
                .scaleEffect(Self.breath(at: time))
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .onAppear { start = Date() }
    }

    /// Rive "Breathe": a slow 2 % swell, 3 s each.
    private static func breath(at time: Double) -> CGFloat {
        1 + 0.02 * (1 - cos(2 * .pi * time / 3)) / 2
    }

    /// Rive "Blink": two quick blinks close together, then a pause (4.2 s loop). 1 is eyes shut.
    private static func blink(at time: Double) -> Double {
        let phase = time.truncatingRemainder(dividingBy: 4.2)
        let half = 0.08
        return [0.75, 1.0].map { max(0, 1 - abs(phase - $0) / half) }.max() ?? 0
    }

    /// Rive "Sparkle": two twinkles, then a pause (5 s loop). 1 is the brightest point.
    private static func twinkle(at time: Double) -> Double {
        let phase = time.truncatingRemainder(dividingBy: 5)
        let length = 0.6
        return [0.3, 1.25].map { start in
            let local = phase - start
            return local >= 0 && local <= length ? sin(.pi * local / length) : 0
        }.max() ?? 0
    }
}

/// One of the white slits in the bird's mask, traced in the 408 × 456 px of `ShooLogo@3x`.
/// Filled with the mask colour it closes the eye.
private struct EyeSlit: Shape {
    let points: [CGPoint]

    static let left = [CGPoint(x: 204, y: 205), CGPoint(x: 271, y: 232), CGPoint(x: 280, y: 276),
                       CGPoint(x: 272, y: 277), CGPoint(x: 258, y: 246)]
    static let right = [CGPoint(x: 341, y: 222), CGPoint(x: 341, y: 236), CGPoint(x: 331, y: 243),
                        CGPoint(x: 327, y: 287), CGPoint(x: 323, y: 287), CGPoint(x: 322, y: 238)]

    func path(in rect: CGRect) -> Path {
        let scale = CGSize(width: rect.width / 408, height: rect.height / 456)
        return Path { path in
            path.addLines(points.map { CGPoint(x: rect.minX + $0.x * scale.width, y: rect.minY + $0.y * scale.height) })
            path.closeSubpath()
        }
    }
}

/// Four-point star with a thin waist, like the sparkle on the app icon.
private struct SparkleStar: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        return Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.midY), control: center)
            path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.maxY), control: center)
            path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.midY), control: center)
            path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.minY), control: center)
        }
    }
}

#Preview {
    ShooBirdLogo()
        .padding(40)
        .background(Color(hex: 0x46A7FF))
}
