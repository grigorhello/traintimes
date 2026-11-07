import SnapshotTesting
import SwiftUI
import XCTest
@testable import TrainTimes

/// Proves the snapshot pipeline end to end. Replaced by the app shell snapshots in TT-104.
final class RootViewSnapshotTests: XCTestCase {
    @MainActor
    func testRootViewLight() {
        assertSnapshot(
            of: RootView(),
            as: .image(perceptualPrecision: 0.98, layout: .device(config: .iPhone13), traits: UITraitCollection(userInterfaceStyle: .light))
        )
    }

    @MainActor
    func testRootViewDark() {
        assertSnapshot(
            of: RootView(),
            as: .image(perceptualPrecision: 0.98, layout: .device(config: .iPhone13), traits: UITraitCollection(userInterfaceStyle: .dark))
        )
    }
}
