import SnapshotTesting
import SwiftUI
import XCTest
@testable import TrainTimes

/// Trip details against design/frames/trip-details*.png (TT-163) and the Delay-A boards (TT-207), light and dark: the 7:32 AM
/// train delayed 9 min with an alert, on time, a later delayed train, the 7:58 AM express train on the timetable only, a cancelled train, a 12-stop trip scrolled to its end, and a train
/// after it has left, the alert bar's day panel (TT-192), and a train boarding at its platform (TT-233). The sheet content is drawn on its own in the key window; the system draws the grabber.
final class TripDetailsSnapshotTests: XCTestCase {
    @MainActor func testDelayedLight() async throws { snap(try await .loadedFixture(.delayed, hasAlert: true), .light) }
    @MainActor func testDelayedDark() async throws { snap(try await .loadedFixture(.delayed, hasAlert: true), .dark) }
    @MainActor func testScheduledLight() async throws { snap(try await .timetableOnlyFixture(), .light) }
    @MainActor func testScheduledDark() async throws { snap(try await .timetableOnlyFixture(), .dark) }
    @MainActor func testCancelledLight() async throws { snap(try await .loadedFixture(.cancelled, hasAlert: true), .light) }
    @MainActor func testCancelledDark() async throws { snap(try await .loadedFixture(.cancelled, hasAlert: true), .dark) }
    /// TT-207 (*Delay-A*): every train that has not left shows the hero; the on-time next train counts down, a later train
    /// (the 7:58 AM express, 9 min late) says "Departs at" with its expected time in delay-ink.
    @MainActor func testOnTimeLight() async throws { snap(try await .loadedFixture(), .light) }
    @MainActor func testOnTimeDark() async throws { snap(try await .loadedFixture(), .dark) }
    @MainActor func testLaterDelayedLight() async throws { snap(try await .laterDelayedFixture(), .light) }
    @MainActor func testLaterDelayedDark() async throws { snap(try await .laterDelayedFixture(), .dark) }
    /// The long trip after it left (7:10 AM), so the whole stop list shows and scrolls to its end.
    @MainActor func testEndLight() async throws { snap(try await .longTripFixture(hour: 7, minute: 10), .light, startsAtEnd: true) }
    @MainActor func testEndDark() async throws { snap(try await .longTripFixture(hour: 7, minute: 10), .dark, startsAtEnd: true) }
    @MainActor func testDepartedLight() async throws { snap(try await .departedFixture(), .light) }
    @MainActor func testDepartedDark() async throws { snap(try await .departedFixture(), .dark) }
    /// TT-192 (*Alert-Trip-Days-Dark*): the alert on, Repeat tapped: the day panel above the bar, Mon to Fri lit. The
    /// 7:32 AM train is 11 min out with its alert on, so the hero card sits over the folded trip (TT-205, D93).
    @MainActor func testAlertDaysLight() async throws { snap(try await alertDays(), .light) }
    @MainActor func testAlertDaysDark() async throws { snap(try await alertDays(), .dark) }
    /// TT-233 (Card states board 5, "at the platform"): the 7:32 AM train standing at Platform 2, 8 min before it leaves.
    /// The hero's accent outline and tint, "7:32 AM boarding now" in the accent over "8 min", the pill filled.
    @MainActor func testBoardingLight() async throws { snap(try await boarding(), .light) }
    @MainActor func testBoardingDark() async throws { snap(try await boarding(), .dark) }

    /// The 7:32 AM train at 7:24 AM, placed 120 m from Oakville by the train feed, its platform posted.
    @MainActor
    private func boarding() async throws -> TripDetailsViewModel {
        try await TripBoardingRig.opened(TripBoardingRig.nextTrain, hour: 7, minute: 24, metres: 120).model
    }

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
