import SnapshotTesting
import UIKit
import XCTest

/// `comparedAsRecorded` against RideSnapshotTests' light permission sheet reference. A copy one pixel off, in the encoding a
/// key-window capture has, fails swift-snapshot-testing's plain comparison with the numbers CI showed for
/// testPermissionLight, and passes once re-encoded; a real colour change still fails.
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
        let plain = diffing.diffV2(reference, capture)?.0
        XCTAssertEqual(plain.map(Self.numbers), "0.9472656 0.9159375", plain ?? "passed")
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

    /// "0.9472656 0.9159375" from the comparison's message: the share of pixels that match, then the lowest perceptual precision.
    private static func numbers(_ message: String) -> String {
        message
            .split(whereSeparator: { $0 == " " || $0 == "\n" })
            .filter { $0.hasPrefix("0.") && $0 != "0.9999" && $0 != "0.98" }
            .joined(separator: " ")
    }
}
