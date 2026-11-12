import SnapshotTesting
import SwiftUI
import XCTest
@testable import TrainTimes

/// Trip details against design/frames/trip-details*.png (TT-163), light and dark: the 7:32 AM train delayed 9 min with an
/// alert, the 7:58 AM express train on the timetable only, a cancelled train, a 12-stop trip scrolled to its end, and a train
/// after it has left, and the alert bar's day panel (TT-192). The sheet content is drawn on its own in the key window; the system draws the grabber.
final class TripDetailsSnapshotTests: XCTestCase {
    @MainActor func testDelayedLight() async throws { snap(try await .loadedFixture(.delayed, hasAlert: true), .light) }
    @MainActor func testDelayedDark() async throws { snap(try await .loadedFixture(.delayed, hasAlert: true), .dark) }
    @MainActor func testScheduledLight() async throws { snap(try await .timetableOnlyFixture(), .light) }
    @MainActor func testScheduledDark() async throws { snap(try await .timetableOnlyFixture(), .dark) }
    @MainActor func testCancelledLight() async throws { snap(try await .loadedFixture(.cancelled, hasAlert: true), .light) }
    @MainActor func testCancelledDark() async throws { snap(try await .loadedFixture(.cancelled, hasAlert: true), .dark) }
    @MainActor func testEndLight() async throws { snap(try await .longTripFixture(), .light, startsAtEnd: true) }
    @MainActor func testEndDark() async throws { snap(try await .longTripFixture(), .dark, startsAtEnd: true) }
    @MainActor func testDepartedLight() async throws { snap(try await .departedFixture(), .light) }
    @MainActor func testDepartedDark() async throws { snap(try await .departedFixture(), .dark) }
    /// TT-192 (*Alert-Trip-Days-Dark*): the alert on, Repeat tapped: the day panel above the bar, Mon to Fri lit.
    @MainActor func testAlertDaysLight() async throws { snap(try await alertDays(), .light) }
    @MainActor func testAlertDaysDark() async throws { snap(try await alertDays(), .dark) }

    /// The 7:32 AM train with its alert turned on from the bar, and Repeat's day panel open.
    @MainActor
    private func alertDays() async throws -> TripDetailsViewModel {
        let repository = try FixtureScheduleRepository(bundle: Bundle(for: Self.self))
        let rules = AlertFixtures.rules(FakeAlertServer())
        let model = TripDetailsViewModel(
            route: repository.route, key: TripKey(serviceDay: repository.serviceDay, tripId: TripDetailsViewModel.fixtureTripId),
            repository: repository, clock: FixedClock(now: repository.now), alerts: rules,
            bells: AlertBellModel(rules: rules, refusalDelay: .zero, afterPrompt: {})
        )
        await model.load()
        await model.tapAlert()
        model.tapRepeat()
        // Repeat saves Mon to Fri in the bell model's own task: draw the sheet once it has, not while the bell waits.
        for _ in 0..<300 {
            if rules.rules.first?.kind == .repeating, model.bell == .on { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(rules.rules.first?.weekdays, [1, 2, 3, 4, 5])
        return model
    }

    @MainActor
    private func snap(
        _ model: TripDetailsViewModel, _ style: UIUserInterfaceStyle, startsAtEnd: Bool = false,
        testName: String = #function, line: UInt = #line
    ) {
        let view = TripDetailsView(viewModel: model, startsAtEnd: startsAtEnd)
            .environment(\.timeFormatter, TimeFormatter(format: .twelveHour))
            // Dark glass drew 5% of the image differently from one run to the next (CI, TT-163); the close button and the
            // alert capsule are drawn as their solid fallbacks here, and the real glass is checked on the simulator.
            .environment(\.rendersGlass, false)
            // The alerted train is in its departure window: the departure card's Live dot pulses from the clock.
            .environment(\.playsRideMotion, false)
        layOutOnce(view)
        // The whole failure message on one line, so the CI log shows how far the image is from the reference.
        let failure = verifySnapshot(
            of: view,
            as: .image(
                drawHierarchyInKeyWindow: true,
                precision: glassSnapshotPrecision,
                perceptualPrecision: 0.98,
                layout: .device(config: .iPhone17Pro),
                traits: UITraitCollection(userInterfaceStyle: style)
            ).comparedAsRecorded,
            file: #filePath,
            testName: testName,
            line: line
        )
        if let failure {
            XCTFail(failure.replacingOccurrences(of: "\n", with: " | "), line: line)
        }
    }
}
