import SnapshotTesting
import SwiftUI
import XCTest
@testable import TrainTimes

/// Every component state from design/frames/components.png, light and dark (TT-102).
final class ComponentSnapshotTests: XCTestCase {
    @MainActor func testBadgesLight() { snap(BadgesGallery(), .light) }
    @MainActor func testBadgesDark() { snap(BadgesGallery(), .dark) }
    @MainActor func testButtonsLight() { snap(ButtonsGallery(), .light) }
    @MainActor func testButtonsDark() { snap(ButtonsGallery(), .dark) }
    @MainActor func testControlsLight() { snap(ControlsGallery(), .light) }
    @MainActor func testControlsDark() { snap(ControlsGallery(), .dark) }
    @MainActor func testSurfacesLight() { snap(SurfacesGallery(), .light) }
    @MainActor func testSurfacesDark() { snap(SurfacesGallery(), .dark) }

    @MainActor
    private func snap(_ view: some View, _ style: UIUserInterfaceStyle, testName: String = #function, line: UInt = #line) {
        assertSnapshot(
            of: view,
            as: .image(perceptualPrecision: 0.98, layout: .device(config: .iPhone17Pro), traits: UITraitCollection(userInterfaceStyle: style)),
            testName: testName,
            line: line
        )
    }
}

final class TripStatusTests: XCTestCase {
    func testCopyComesFromLocalizableStrings() {
        XCTAssertEqual(TripStatus.onTime.text, "On time")
        XCTAssertEqual(TripStatus.delayed(minutes: 9).text, "Delayed 9 min")
        XCTAssertEqual(TripStatus.stopSkipped.text, "Stop skipped")
        XCTAssertEqual(TripStatus.lastReported(time: "7:29 AM").text, "Last reported 7:29 AM")
        XCTAssertEqual(TripStatus.offline.text, "Offline")
    }

    func testColoursResolveFromTheAssetCatalog() {
        XCTAssertNotNil(UIColor(named: "Accent"))
        XCTAssertNotNil(UIColor(named: "ScheduledFill"))
    }
}
