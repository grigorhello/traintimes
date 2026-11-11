import SnapshotTesting
import UIKit
import XCTest

/// `comparedAsRecorded` against RideSnapshotTests' light permission sheet reference. A copy one pixel off, in the encoding a
/// key-window capture has, fails swift-snapshot-testing's plain comparison the way testPermissionLight did on CI, and
/// passes once re-encoded; a real colour change still fails.
final class ReferenceEncodingTests: XCTestCase {
    @MainActor
    func testOnePixelOffFailsOnlyWithoutTheReferenceEncoding() throws {
        let diffing = Diffing<UIImage>.image(precision: glassSnapshotPrecision, perceptualPrecision: 0.98)
        let reference = try permissionReference(diffing)
        let capture = captureLikeCopy(of: reference) { context in
            // One pixel of the dimmed area a shade lighter (under dE 2), so no byte-for-byte check passes.
            UIColor.white.withAlphaComponent(0.05).setFill()
            context.fill(CGRect(x: 100, y: 100, width: 1.0 / 3, height: 1.0 / 3), blendMode: .normal)
        }
        // The plain comparison fails on its accent pixels: on CI it gave 0.9472656 of pixels / perceptual 0.9158593 here,
        // and 0.9472656 / 0.9159375 for testPermissionLight's real captures. If a library upgrade makes it pass, drop
        // comparedAsRecorded.
        XCTAssertNotNil(diffing.diffV2(reference, capture)?.0)
        XCTAssertNil(diffing.diffV2(reference, recorded(capture, diffing))?.0)
    }

    @MainActor
    func testAColourChangeStillFails() throws {
        let diffing = Diffing<UIImage>.image(precision: glassSnapshotPrecision, perceptualPrecision: 0.98)
        let reference = try permissionReference(diffing)
        let capture = captureLikeCopy(of: reference) { context in
            // The middle of the Continue button in the pressed accent.
            UIColor(named: "AccentPressed")?.setFill()
            context.fill(CGRect(x: 40, y: 650, width: 322, height: 36))
        }
        XCTAssertNotNil(diffing.diffV2(reference, recorded(capture, diffing))?.0)
    }

    /// RideSnapshotTests' light permission sheet reference, loaded as the snapshot library loads it.
    private func permissionReference(_ diffing: Diffing<UIImage>) throws -> UIImage {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Features/TripDetails/__Snapshots__/RideSnapshotTests/testPermissionLight.1.png")
        return diffing.fromData(try Data(contentsOf: url))
    }

    /// The image redrawn in the encoding a key-window capture has (extended-range sRGB), with `change` drawn over it.
    @MainActor
    private func captureLikeCopy(of image: UIImage, change: (UIGraphicsImageRendererContext) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.preferredRange = .extended
        return UIGraphicsImageRenderer(size: image.size, format: format).image { context in
            image.draw(at: .zero)
            change(context)
        }
    }

    /// The image as `comparedAsRecorded` hands it to the comparison.
    private func recorded(_ image: UIImage, _ diffing: Diffing<UIImage>) -> UIImage {
        var result = image
        Snapshotting<UIImage, UIImage>(pathExtension: "png", diffing: diffing, snapshot: { $0 })
            .comparedAsRecorded
            .snapshot(image)
            .run { result = $0 }
        return result
    }
}
