import Testing
import UIKit
@testable import Shoo

struct MascotTests {
    @Test(arguments: Mascot.allCases)
    func everyPoseHasAnAssetWithTheDeclaredShape(pose: Mascot) throws {
        let image = try #require(UIImage(named: pose.assetName), "missing \(pose.assetName)")
        #expect(abs(image.size.width / image.size.height - pose.aspectRatio) < 0.01)
        #expect(image.size.height * image.scale <= 600)
    }

    @Test func peekHandsShareThePeekCanvas() throws {
        let body = try #require(UIImage(named: Mascot.peek.assetName))
        let hands = try #require(UIImage(named: Mascot.peekHandsAssetName))
        #expect(body.size == hands.size)
    }
}
