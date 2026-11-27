import SnapshotTesting
import SwiftUI
import XCTest
@testable import TrainTimes

/// See trains landed on Friday's 7:58 AM card (TT-255, D129; the Alerts canvas's board 52): the day strip on Fri 6, the
/// 7:32 AM card above it, and the card frozen at the top of its swell, 1.035 with the raised shadow and its bell, On for
/// the Mon–Fri alert, in its pop; light and dark. Glass is drawn as its solid fallback, and the system tab bar at the
/// bottom is left out (`keepingTop`), which in dark settles in one of two looks from run to run.
final class ScheduleLandingSnapshotTests: XCTestCase {
    @MainActor func testLandedCardSwellsLight() async throws { snap(try await landed(), .light) }
    @MainActor func testLandedCardSwellsDark() async throws { snap(try await landed(), .dark) }

    @MainActor
    private func landed() async throws -> (ScheduleViewModel, AlertBellModel) {
        let schedule = try await ScheduleViewModel.loadedFixture()
        let route = try XCTUnwrap(schedule.route)
        let friday = schedule.days[1]
        let key = TripKey(serviceDay: friday, tripId: "LW-0758-20261105")
        await schedule.land(.card(key), on: route, day: friday)
        XCTAssertEqual(schedule.landedCard, key)

        let trip = try XCTUnwrap(schedule.departures.first { $0.trip.key == key }?.trip)
        let rules = AlertRules(
            server: FixtureAlertServer(delay: .zero), push: FixturePushRegistration(),
            permissions: FakeNotificationPermission(.allowed), defaults: nil
        )
        let saved = await rules.commit(AlertRule(kind: .repeating, trip: trip, route: route, weekdays: [1, 2, 3, 4, 5]))
        XCTAssertTrue(saved)
        return (schedule, AlertBellModel(rules: rules))
    }

    @MainActor
    private func snap(_ models: (ScheduleViewModel, AlertBellModel), _ style: UIUserInterfaceStyle, testName: String = #function, line: UInt = #line) {
        let view = RootView(schedule: models.0, settings: AppSettings(defaults: .ephemeral()), bells: models.1)
            .environment(\.rendersGlass, false)
            .environment(\.landingSwellFrozenAt, LandingSwell.peakTime)
        layOutOnce(view)
        assertSnapshot(
            of: view,
            as: .image(
                drawHierarchyInKeyWindow: true,
                precision: glassSnapshotPrecision,
                perceptualPrecision: 0.98,
                layout: .device(config: .iPhone17Pro),
                traits: UITraitCollection(userInterfaceStyle: style)
            ).keepingTop(Self.keptHeight).comparedAsRecorded,
            testName: testName,
            line: line
        )
    }

    /// The header and the timeline down to above the tab bar.
    private static let keptHeight: CGFloat = 760
}
