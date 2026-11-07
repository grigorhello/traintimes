import SnapshotTesting
import SwiftUI
import XCTest
@testable import TrainTimes

@MainActor
final class AppRouterTests: XCTestCase {
    func testLaunchLandsOnScheduleWithNothingPresented() {
        let router = AppRouter()
        XCTAssertEqual(router.selectedTab, .schedule)
        XCTAssertTrue(router.schedulePath.isEmpty)
        XCTAssertNil(router.presentedSheet)
        XCTAssertFalse(router.showsAlertsDot)
    }

    func testOpenSettingsPushesSettingsOnSchedule() {
        let router = AppRouter()
        router.selectedTab = .alerts
        router.openSettings()
        XCTAssertEqual(router.selectedTab, .schedule)
        XCTAssertEqual(router.schedulePath, [.settings])
    }

    func testSheetsPresentAndDismiss() {
        let router = AppRouter()
        router.present(.tripDetails)
        XCTAssertEqual(router.presentedSheet, .tripDetails)
        router.present(.lineNotices)
        XCTAssertEqual(router.presentedSheet, .lineNotices)
        router.dismissSheet()
        XCTAssertNil(router.presentedSheet)
    }

    func testClassicBarsAreRequested() {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "UIDesignRequiresCompatibility") as? Bool, true)
    }
}

/// Shell states against design/frames/schedule-timeline.png (header and tab bar), light and dark.
final class AppShellSnapshotTests: XCTestCase {
    @MainActor func testScheduleTabLight() { snap(RootView(), .light) }
    @MainActor func testScheduleTabDark() { snap(RootView(), .dark) }
    @MainActor func testAlertsDotLight() { snap(RootView(router: dotRouter()), .light) }
    @MainActor func testAlertsDotDark() { snap(RootView(router: dotRouter()), .dark) }

    @MainActor
    private func dotRouter() -> AppRouter {
        let router = AppRouter()
        router.showsAlertsDot = true
        return router
    }

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
