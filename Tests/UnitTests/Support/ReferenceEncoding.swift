import SnapshotTesting
import UIKit

extension Snapshotting where Format == UIImage {
    /// The capture re-encoded as a PNG, the way swift-snapshot-testing writes references, before it is compared. Every
    /// `drawHierarchyInKeyWindow` snapshot uses this.
    ///
    /// A key-window capture is extended-range sRGB, and its reference is a 16-bit Display P3 PNG. When the two are not equal
    /// byte for byte, swift-snapshot-testing 1.19.7 compares their raw numbers with colour management off
    /// (`perceptuallyCompare`), so saturated pixels read several dE off (about 8.4 for the light accent, about 4 for the
    /// dark one), and one stray pixel fails the whole snapshot with the same numbers each time.
    /// RideSnapshotTests.testPermissionLight failed this way in about a third of CI runs (0.9472656 of pixels /
    /// 0.9159375: its accent pixels). In the reference's encoding, `precision` and `perceptualPrecision` measure the real
    /// difference.
    var comparedAsRecorded: Snapshotting {
        let capture = snapshot
        return Snapshotting(pathExtension: pathExtension, diffing: diffing, asyncSnapshot: { value in
            capture(value).map { image in
                image.pngData().flatMap { UIImage(data: $0, scale: image.scale) } ?? image
            }
        })
    }
}
