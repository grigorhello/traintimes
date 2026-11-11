import SnapshotTesting
import SwiftUI
import XCTest
@testable import TrainTimes

/// The filled bell and the glass capsule on Schedule (TT-141, TT-191) against the Alerts-Spec board: the 7:32 AM train
/// delayed to 7:41 AM with its alert on and "Alert on · 7:32 AM · Repeat" above the tab bar, then Repeat tapped, the
/// capsule grown into the day panel with Mon to Fri lit and the timeline faded under it; light and dark. The capsule's
/// glass is off (`\.rendersGlass`), as in the other control snapshots.
final class AlertBellSnapshotTests: XCTestCase {
    @MainActor func testAlertOnLight() async throws { snap(try await alertOn(), .light) }
    @MainActor func testAlertOnDark() async throws { snap(try await alertOn(), .dark) }
    @MainActor func testDayPanelLight() async throws { snap(try await dayPanel(), .light) }
    @MainActor func testDayPanelDark() async throws { snap(try await dayPanel(), .dark) }

    @MainActor
    private func alertOn() async throws -> (ScheduleViewModel, AlertBellModel) {
        let schedule = try await ScheduleViewModel.loadedFixture(.delayed)
        let route = try XCTUnwrap(schedule.route)
        let trip = try XCTUnwrap(schedule.departures.first { $0.trip.key.tripId == "LW-0732-20261105" }?.trip)
        let rules = AlertRules(
            server: FixtureAlertServer(delay: .zero), push: FixturePushRegistration(),
            permissions: FakeNotificationPermission(.allowed), defaults: nil
        )
        let bells = AlertBellModel(rules: rules, actionDuration: .seconds(600))
        _ = await bells.tap(trip, on: route)
        return (schedule, bells)
    }

    @MainActor
    private func dayPanel() async throws -> (ScheduleViewModel, AlertBellModel) {
        let (schedule, bells) = try await alertOn()
        bells.repeatTapped()
        for _ in 0..<200 where bells.rules.rules.first?.kind != .repeating {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(bells.rules.rules.first?.weekdays, [1, 2, 3, 4, 5])
        return (schedule, bells)
    }

    @MainActor
    private func snap(_ models: (ScheduleViewModel, AlertBellModel), _ style: UIUserInterfaceStyle, testName: String = #function, line: UInt = #line) {
        let view = RootView(schedule: models.0, settings: AppSettings(defaults: .ephemeral()), bells: models.1)
            .environment(\.rendersGlass, false)
        layOutOnce(view)
        assertSnapshot(
            of: view,
            as: .image(
                drawHierarchyInKeyWindow: true,
                precision: glassSnapshotPrecision,
                perceptualPrecision: 0.98,
                layout: .device(config: .iPhone17Pro),
                traits: UITraitCollection(userInterfaceStyle: style)
            ).comparedAsRecorded,
            testName: testName,
            line: line
        )
    }
}
