import XCTest
@testable import TrainTimes

/// TT-203 (D86): which trains have left, and when their step up plays.
@MainActor
final class ScheduleDepartedTests: XCTestCase {
    private let thursday = ServiceDay(year: 2026, month: 11, day: 5)
    private let formatter = TimeFormatter(format: .twelveHour)

    private func model(
        _ scenario: FixtureScheduleRepository.Scenario = .normal, at hour: Int, _ minute: Int, on day: ServiceDay? = nil
    ) async throws -> (ScheduleViewModel, TestClock) {
        let repository = try FixtureScheduleRepository(scenario: scenario, bundle: Bundle(for: ScheduleDepartedTests.self))
        let clock = TestClock(now: (day ?? thursday).date(hour: hour, minute: minute))
        let model = ScheduleViewModel(route: repository.route, repository: repository, clock: clock)
        await model.loadIfNeeded()
        return (model, clock)
    }

    // MARK: The rule

    /// At its expected departure the train has left: "Departed", and the next one leads.
    func testATrainHasLeftAtItsDepartureTime() async throws {
        let (model, _) = try await model(at: 7, 32)
        let cards = model.cards(formatter)
        XCTAssertEqual(cards.map(\.isDeparted), [true, false, false, false])
        XCTAssertEqual(cards[0].shownStatus, .departed)
        XCTAssertFalse(cards[0].isNext)
        XCTAssertTrue(cards[1].isNext)
        XCTAssertEqual(cards[1].shownStatus, cards[1].status)
    }

    /// A delayed train leaves at its expected time, not its scheduled one.
    func testADelayedTrainLeavesAtItsExpectedTime() async throws {
        let (late, _) = try await model(.delayed, at: 7, 35)
        XCTAssertFalse(try XCTUnwrap(late.cards(formatter).first).isDeparted)
        let (gone, _) = try await model(.delayed, at: 7, 41)
        let card = try XCTUnwrap(gone.cards(formatter).first)
        XCTAssertTrue(card.isDeparted)
        XCTAssertEqual(card.shownStatus, .departed)
    }

    /// A cancelled train goes flat after its time and keeps "Cancelled".
    func testACancelledTrainKeepsItsStatus() async throws {
        let (model, _) = try await model(.cancelled, at: 7, 33)
        let card = try XCTUnwrap(model.cards(formatter).first)
        XCTAssertTrue(card.isDeparted)
        XCTAssertEqual(card.shownStatus, .cancelled)
    }

    /// Every train on a past day has left, and stays in its place.
    func testAPastDayIsAllDepartedInPlace() async throws {
        let (model, _) = try await model(at: 7, 0, on: thursday.adding(days: 1))
        await model.select(thursday)
        XCTAssertTrue(model.isPastDay)
        let cards = model.cards(formatter)
        XCTAssertFalse(cards.isEmpty)
        XCTAssertTrue(cards.allSatisfy(\.isDeparted))
        XCTAssertFalse(model.layout.cards.contains { $0.isSteppedUp })
    }

    // MARK: The play

    /// The minute tick that makes a train leave plays its step up, with the Now line's 7 pt glide and the next train's lead.
    func testTheTickThatMakesATrainLeavePlays() async throws {
        let (model, clock) = try await model(at: 7, 31)
        XCTAssertEqual(model.departureRequest, 0, "Nothing on launch")
        clock.advance(minutes: 1)
        model.tick()
        XCTAssertEqual(model.departureRequest, 1)
        XCTAssertEqual(model.departing.map(\.tripId), ["LW-0732-20261105"])
        XCTAssertEqual(model.departureLead?.tripId, "LW-0732-20261105")
        XCTAssertEqual(model.departureNext?.tripId, "LW-0758-20261105")
        XCTAssertEqual(model.departureGlide, TTTimeline.pointsPerMinute, accuracy: 0.001)
        clock.advance(minutes: 1)
        model.tick()
        XCTAssertEqual(model.departureRequest, 1, "A tick with no train leaving plays nothing")
    }

    /// Trains already gone on launch, or gone while the app was away, are drawn at rest.
    func testNoPlayOnLaunchOrAfterAnAbsence() async throws {
        let (launched, _) = try await model(at: 7, 40)
        XCTAssertEqual(launched.departureRequest, 0)
        XCTAssertTrue(try XCTUnwrap(launched.layout.cards.first).isSteppedUp, "Drawn in its departed place")

        let (away, clock) = try await model(at: 7, 31)
        clock.advance(minutes: 3)
        away.tick()
        XCTAssertEqual(away.departureRequest, 0, "Left two minutes ago, while the app was away")

        let (shown, shownClock) = try await model(at: 7, 31)
        shownClock.advance(minutes: 1)
        shown.tick(playsDepartures: false)
        XCTAssertEqual(shown.departureRequest, 0, "The first tick after the screen shows")
    }

    /// A new set of trains never plays: back to Today from another day after a train left.
    func testNoPlayOnADayChange() async throws {
        let (model, clock) = try await model(at: 7, 31)
        await model.select(model.days[1])
        clock.advance(minutes: 2)
        model.tick()
        await model.backToNow()
        XCTAssertEqual(model.departureRequest, 0)
        XCTAssertTrue(try XCTUnwrap(model.cards(formatter).first).isDeparted)
    }

    /// A cancelled train goes flat with no play.
    func testACancelledTrainDoesNotPlay() async throws {
        let (model, clock) = try await model(.cancelled, at: 7, 31)
        clock.advance(minutes: 1)
        model.tick()
        XCTAssertEqual(model.departureRequest, 0)
    }
}
