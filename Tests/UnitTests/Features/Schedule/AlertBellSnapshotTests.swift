import SnapshotTesting
import SwiftUI
import XCTest
@testable import TrainTimes

/// The filled bell and the toast against design/frames/schedule-delayed.png (TT-141): the 7:32 AM train delayed to
/// 7:41 AM with its alert on, and "Alert on for the 7:32 AM train · Repeat" above the tab bar, light and dark. With
/// notifications off (TT-190, the Alert-Flow-Denied frame): the 7:32 AM alert's bell is crossed, and its tap leaves
/// "Notifications are off · Turn on" above the tab bar.
final class AlertBellSnapshotTests: XCTestCase {
    @MainActor func testAlertOnLight() async throws { snap(try await alertOn(), .light) }
    @MainActor func testAlertOnDark() async throws { snap(try await alertOn(), .dark) }
    @MainActor func testNotificationsOffLight() async throws { snap(try await notificationsOff(), .light) }
    @MainActor func testNotificationsOffDark() async throws { snap(try await notificationsOff(), .dark) }

    @MainActor
    private func alertOn() async throws -> (ScheduleViewModel, AlertBellModel) {
        let schedule = try await ScheduleViewModel.loadedFixture(.delayed)
        let route = try XCTUnwrap(schedule.route)
        let trip = try XCTUnwrap(schedule.departures.first { $0.trip.key.tripId == "LW-0732-20261105" }?.trip)
        let rules = AlertRules(
            server: FixtureAlertServer(delay: .zero), push: FixturePushRegistration(),
            permissions: FakeNotificationPermission(.allowed), defaults: nil
        )
        let bells = AlertBellModel(rules: rules, toastDuration: .seconds(600))
        await bells.tap(trip, on: route)
        return (schedule, bells)
    }

    @MainActor
    private func notificationsOff() async throws -> (ScheduleViewModel, AlertBellModel) {
        let schedule = try await ScheduleViewModel.loadedFixture(.delayed)
        let route = try XCTUnwrap(schedule.route)
        let trip = try XCTUnwrap(schedule.departures.first { $0.trip.key.tripId == "LW-0732-20261105" }?.trip)
        let rules = AlertRules(
            server: FixtureAlertServer(delay: .zero), push: FixturePushRegistration(),
            permissions: FakeNotificationPermission(.off), defaults: nil
        )
        await rules.save(AlertRule(kind: .thisTrip, trip: trip, route: route))
        let bells = AlertBellModel(rules: rules, toastDuration: .seconds(600), refusalDelay: .zero)
        await bells.tap(trip, on: route)
        return (schedule, bells)
    }

    @MainActor
    private func snap(_ models: (ScheduleViewModel, AlertBellModel), _ style: UIUserInterfaceStyle, testName: String = #function, line: UInt = #line) {
        let view = RootView(schedule: models.0, settings: AppSettings(defaults: .ephemeral()), bells: models.1)
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
