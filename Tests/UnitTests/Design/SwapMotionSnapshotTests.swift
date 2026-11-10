import SnapshotTesting
import SwiftUI
import XCTest
@testable import TrainTimes

/// The swap motion's four key frames (TT-165, D59) against the Swap-Motion-B board and the Motion-Spec row on the canvas,
/// light and dark: 0 ms (the names have traded in the data and still stand in the other's row, arrows a half turn back,
/// button pressed), 130 ms (passing on arcs, lifted on a pill, the first dot lit), 300 ms (landing, the pill fading, the
/// arrows swinging past upright) and 650 ms (at rest but for the arrows and the pin). The card is drawn as the data says
/// after a swap: Union Station GO over Oakville GO. Glass is off, as in the other control snapshots.
final class SwapMotionSnapshotTests: XCTestCase {
    @MainActor func testTapLight() { snap(0, .light) }
    @MainActor func testTapDark() { snap(0, .dark) }
    @MainActor func testPassLight() { snap(0.13, .light) }
    @MainActor func testPassDark() { snap(0.13, .dark) }
    @MainActor func testLandLight() { snap(0.30, .light) }
    @MainActor func testLandDark() { snap(0.30, .dark) }
    @MainActor func testRestLight() { snap(0.65, .light) }
    @MainActor func testRestDark() { snap(0.65, .dark) }

    @MainActor
    private func snap(_ elapsed: TimeInterval, _ style: UIUserInterfaceStyle, testName: String = #function, line: UInt = #line) {
        let view = RouteCard(
            from: "Union Station GO", to: "Oakville GO", fromID: "from", toID: "to", onTap: { _ in }, swapID: "swap", onSwap: {}
        )
        .environment(\.swapFrozenAt, elapsed)
        .environment(\.rendersGlass, false)
        .padding(TTSpace.s5)
        .frame(maxWidth: .infinity)
        .background(TTColor.canvas)
        let traits = UITraitCollection(traitsFrom: [UITraitCollection(userInterfaceStyle: style), UITraitCollection(displayScale: 3)])
        assertSnapshot(
            of: view,
            as: .image(perceptualPrecision: 0.98, layout: .fixed(width: 402, height: 176), traits: traits),
            testName: testName,
            line: line
        )
    }
}
