import SwiftUI
import Testing
import UIKit
@testable import Shoo

/// U-17 (DT-01, fase 28g): the Detail footer's question must sit on a solid band. The footer overlays the scroll
/// content, so the test reads the footer's own background, not frames: rendered over black, any see-through
/// shows as a darker pixel. Fixed width 375 pt and `.large` text, so the result does not depend on the simulator.
@MainActor
struct DetailFooterTests {
    /// The question's top edge.
    private static let questionTop = DetailFooter.topPadding
    /// A column inside the 24 pt side padding, where no letter is drawn.
    private static let paddingColumn: CGFloat = 4

    @Test(arguments: [
        (true, nil),
        (false, nil),
        // "Gagal menyimpan": the error line makes the footer taller.
        (true, .connection),
    ] as [(Bool, DetailModel.VerdictError?)])
    func questionSitsOnASolidBand(isBlocked: Bool, failure: DetailModel.VerdictError?) throws {
        #expect(DetailFooter.fadeHeight < DetailFooter.topPadding, "the fade must end above the question")
        let footer = DetailFooter(
            verdict: nil, viewerDeviceId: nil, canValidate: true, failure: failure,
            ownerName: nil, isBlocked: isBlocked, onDecide: { _ in }
        )
        .frame(width: 375)
        .environment(\.dynamicTypeSize, .large)
        .environment(\.locale, Locale(identifier: "en"))
        .environment(\.colorScheme, .light)
        .background(Color.black)

        let renderer = ImageRenderer(content: footer)
        renderer.proposedSize = ProposedViewSize(width: 375, height: nil)
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        let pixel = try #require(Self.rgba(image, x: Int(Self.paddingColumn), y: Int(Self.questionTop)))
        // Over black, the footer colour #F5F6FC appears only where the band is fully opaque.
        let footer255: (r: Int, g: Int, b: Int) = (0xF5, 0xF6, 0xFC)
        let alpha = Double(pixel.b) / Double(footer255.b)
        #expect(
            abs(pixel.r - footer255.r) <= 2 && abs(pixel.g - footer255.g) <= 2 && abs(pixel.b - footer255.b) <= 2,
            "footer background at the question's top edge is \(pixel), alpha ≈ \(String(format: "%.2f", alpha)), want #F5F6FC at 1.0"
        )
    }

    /// The pixel at (x, y) as 8-bit sRGB.
    private static func rgba(_ image: CGImage, x: Int, y: Int) -> (r: Int, g: Int, b: Int, a: Int)? {
        guard x < image.width, y < image.height,
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var bytes = [UInt8](repeating: 0, count: 4)
        let drawn: Bool = bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            // CGContext's origin is bottom-left: shift the image so pixel (x, y from the top) lands on (0, 0).
            context.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
            return true
        }
        guard drawn else { return nil }
        return (Int(bytes[0]), Int(bytes[1]), Int(bytes[2]), Int(bytes[3]))
    }
}
