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
/// Drawn in the host app's key window so the tab bar, navigation stack and safe areas render as on the simulator.
final class AppShellSnapshotTests: XCTestCase {
    @MainActor func testScheduleTabLight() async throws { snap(try await root(), .light) }
    @MainActor func testScheduleTabDark() async throws { snap(try await root(), .dark) }
    @MainActor func testAlertsDotLight() async throws { snap(try await root(dotRouter()), .light) }
    @MainActor func testAlertsDotDark() async throws { snap(try await root(dotRouter()), .dark) }
    @MainActor func testAlertsTabLight() async throws { snap(try await root(alertsRouter()), .light) }
    @MainActor func testAlertsTabDark() async throws { snap(try await root(alertsRouter()), .dark) }

    /// A loaded schedule, so the snapshot never races the first load (TT-112), and fresh settings,
    /// so an Appearance stored by an earlier run never overrides the snapshot's style (TT-105).
    @MainActor
    private func root(_ router: AppRouter = AppRouter()) async throws -> RootView {
        RootView(router: router, schedule: try await .loadedFixture(), settings: AppSettings(defaults: .ephemeral()))
    }

    @MainActor
    private func dotRouter() -> AppRouter {
        let router = AppRouter()
        router.showsAlertsDot = true
        return router
    }

    @MainActor
    private func alertsRouter() -> AppRouter {
        let router = AppRouter()
        router.selectedTab = .alerts
        return router
    }

    @MainActor
    private func snap(_ view: some View, _ style: UIUserInterfaceStyle, testName: String = #function, line: UInt = #line) {
        assertSnapshot(
            of: view,
            as: .image(
                drawHierarchyInKeyWindow: true,
                perceptualPrecision: 0.98,
                layout: .device(config: .iPhone17Pro),
                traits: UITraitCollection(userInterfaceStyle: style)
            ),
            testName: testName,
            line: line
        )
    }
}
