import Testing
import SwiftUI
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

    /// Figma 2447:13710: the peek pose is 147 x 104 and the sheet's edge cuts it 97 pt down.
    @Test func peekSheetPlacesShooLikeFigma() {
        #expect(PeekSheetChrome<EmptyView>.rise == 97)
        #expect(abs(PeekSheetChrome<EmptyView>.poseWidth - 147) < 0.5)
        #expect(PeekSheetChrome<EmptyView>.trailingInset == 56)
    }
}
