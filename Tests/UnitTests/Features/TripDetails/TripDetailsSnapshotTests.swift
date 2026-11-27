import SnapshotTesting
import SwiftUI
import XCTest
@testable import TrainTimes

/// Trip details against design/frames/trip-details*.png (TT-163) and the Delay-A boards (TT-207), light and dark: the 7:32 AM
/// train delayed 9 min with an alert, on time, a later delayed train, the 7:58 AM express train on the timetable only, a cancelled train, a 12-stop trip scrolled to its end, and a train
/// after it has left, the alert bar's day panel (TT-192), and a train boarding at its platform (TT-233). The sheet content is drawn on its own in the key window; the system draws the grabber.
final class TripDetailsSnapshotTests: XCTestCase {
    @MainActor func testDelayedLight() async throws { snap(try await .loadedFixture(.delayed), .light) }
    @MainActor func testDelayedDark() async throws { snap(try await .loadedFixture(.delayed), .dark) }
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
    /// Alert first (TT-254, D129; the Alerts canvas's boards 45 to 50): the alert card on top of the sheet.
    @MainActor func testAlertRepeatLight() async throws { snap(try await alerted(.repeating), .light) }
    @MainActor func testAlertRepeatDark() async throws { snap(try await alerted(.repeating), .dark) }
    @MainActor func testAlertOnceLight() async throws { snap(try await alerted(.once), .light) }
    @MainActor func testAlertOnceDark() async throws { snap(try await alerted(.once), .dark) }
    @MainActor func testAlertTomorrowLight() async throws { snap(try await alerted(.tomorrow), .light) }
    @MainActor func testAlertTomorrowDark() async throws { snap(try await alerted(.tomorrow), .dark) }
    @MainActor func testAlertOffLight() async throws { snap(try await alerted(.off), .light) }
    @MainActor func testAlertOffDark() async throws { snap(try await alerted(.off), .dark) }
    @MainActor func testAlertChangedLight() async throws { snap(try await alerted(.changed), .light) }
    @MainActor func testAlertChangedDark() async throws { snap(try await alerted(.changed), .dark) }
    /// TT-233 (Card states board 5, "at the platform"): the 7:32 AM train standing at Platform 2, 8 min before it leaves.
    /// The hero's accent outline and tint, "7:32 AM boarding now" in the accent over "8 min", the pill filled.
    @MainActor func testBoardingLight() async throws { snap(try await boarding(), .light) }
    @MainActor func testBoardingDark() async throws { snap(try await boarding(), .dark) }
    /// TT-246 (D123): 3:31 AM, the 7:32 AM train 241 min away: the hero's number in hours, "4 h 1 min", shrunk to fit.
    @MainActor func testLongWaitLight() async throws { snap(try await .loadedFixture(minutesLater: -230), .light) }
    @MainActor func testLongWaitDark() async throws { snap(try await .loadedFixture(minutesLater: -230), .dark) }

    /// The 7:32 AM train at 7:24 AM, placed 120 m from Oakville by the train feed, its platform posted.
    @MainActor
    private func boarding() async throws -> TripDetailsViewModel {
        try await TripBoardingRig.opened(TripBoardingRig.nextTrain, hour: 7, minute: 24, metres: 120).model
    }

    private enum AlertScene {
        case repeating, once, tomorrow, off, changed
    }

    /// Board 45: Thu 7:21 AM, the 7:32 with a Mon to Fri alert, 11 min out, "I’m on board" alone in its window. Board 46:
    /// the 7:58 express with a one-day alert, "Once, today", Thursday's ring, counting 37 min as its Alerts card does.
    /// Boards 47 and 48: Thu 8:05 PM, tomorrow's 7:32 with the Mon to Fri alert, switched on, then off. Board 50: Time
    /// changed, the card alone.
    @MainActor
    private func alerted(_ scene: AlertScene) async throws -> TripDetailsViewModel {
        let repository = try FixtureScheduleRepository(bundle: Bundle(for: Self.self))
        let today = repository.serviceDay
        let route = repository.route
        func train(_ id: String, on day: ServiceDay) async throws -> Trip {
            try XCTUnwrap(try await repository.trips(for: route, on: day).first { $0.key.tripId == id })
        }
        let weekdays = [1, 2, 3, 4, 5]
        switch scene {
        case .repeating:
            let rules = AlertFixtures.rules(FakeAlertServer())
            let trip = try await train(TripDetailsViewModel.fixtureTripId, on: today)
            await rules.save(AlertRule(kind: .repeating, trip: trip, route: route, weekdays: weekdays))
            return try await TripDetailsViewModel.onBoardFixture(alerts: rules)
        case .once:
            let rules = AlertFixtures.rules(FakeAlertServer())
            let trip = try await train("LW-0758-20261105", on: today)
            await rules.save(AlertRule(kind: .thisTrip, trip: trip, route: route))
            return await model(trip.key, rules: rules, at: repository.now, repository: repository)
        case .tomorrow, .off:
            let rules = AlertFixtures.rules(FakeAlertServer())
            let trip = try await train(TripDetailsViewModel.fixtureTripId, on: today.adding(days: 1))
            await rules.save(AlertRule(kind: .repeating, trip: trip, route: route, weekdays: weekdays, paused: scene == .off))
            return await model(trip.key, rules: rules, at: today.date(hour: 20, minute: 5), repository: repository)
        case .changed:
            let trip = try await train(TripDetailsViewModel.fixtureTripId, on: today)
            let rule = AlertRule(id: "changed", kind: .repeating, trip: trip, route: route, weekdays: weekdays)
            let rules = await AlertsFixtures.rules(FakeAlertServer(), reviewNeeded: [rule])
            return await model(trip.key, rules: rules, at: repository.now, repository: repository, alertID: rule.id)
        }
    }

    @MainActor
    private func model(
        _ key: TripKey, rules: AlertRules, at now: Date, repository: FixtureScheduleRepository, alertID: AlertRule.ID? = nil
    ) async -> TripDetailsViewModel {
        let model = TripDetailsViewModel(
            route: repository.route, key: key, repository: repository, clock: FixedClock(now: now), alerts: rules,
            bells: AlertBellModel(rules: rules, refusalDelay: .zero, afterPrompt: {}), alertID: alertID
        )
        await model.load()
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
