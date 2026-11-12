import XCTest
@testable import TrainTimes

/// TT-113: the cards, the next usable train and the rail labels the timeline draws.
@MainActor
final class TimelineCardsTests: XCTestCase {
    private let formatter = TimeFormatter(format: .twelveHour)

    func testNextUsableTrainLeadsWithMinutesUntilDeparture() async throws {
        let cards = try await ScheduleViewModel.loadedFixture().cards(formatter)
        XCTAssertEqual(cards.map(\.time), ["7:32 AM", "7:58 AM", "8:21 AM", "8:50 AM"])
        XCTAssertEqual(cards.map(\.isNext), [true, false, false, false])

        let next = cards[0]
        XCTAssertEqual(next.relativeTime, "in 11 min")
        XCTAssertEqual(next.status, .onTime)
        XCTAssertEqual(next.arrivalTime, "8:12 AM")
        XCTAssertEqual(next.tripLength, "40 min")
        XCTAssertEqual(next.platformValue, "2")
        XCTAssertTrue(next.hasPlatform)
        XCTAssertFalse(next.isExpress)

        XCTAssertNil(cards[1].relativeTime, "No other card shows a relative time")
        XCTAssertFalse(cards[1].hasPlatform, "The pill holds a dash until GO publishes the platform")
        XCTAssertTrue(cards[1].isExpress, "Express from the stopping-pattern rule (D35)")
        XCTAssertEqual(cards[2].status, .scheduled, "No live data for this trip: Scheduled, never On time (D50)")
    }

    func testNextTrainMovesOnOnceItsTimePasses() async throws {
        let model = try await ScheduleViewModel.loadedFixture(minutesLater: 12) // 7:33 AM
        let cards = model.cards(formatter)
        XCTAssertEqual(model.nextDepartureId?.tripId, "LW-0758-20261105")
        XCTAssertEqual(cards[1].relativeTime, "in 25 min")
        XCTAssertFalse(cards[0].isNext, "7:32 AM has left")
    }

    /// Once a minute the Now line moves 7 pt closer to the next train and "in N min" counts down.
    func testMinuteTickMovesNowAndCountsDown() async throws {
        let repository = try FixtureScheduleRepository(bundle: Bundle(for: TimelineCardsTests.self))
        let clock = TestClock(now: repository.now)
        let model = ScheduleViewModel(route: repository.route, repository: repository, clock: clock)
        await model.loadIfNeeded()
        let before = try XCTUnwrap(model.layout.cards.first).markerY - XCTUnwrap(model.layout.nowY)
        XCTAssertEqual(model.cards(formatter)[0].relativeTime, "in 11 min")

        clock.advance(minutes: 1)
        model.tick()
        let after = try XCTUnwrap(model.layout.cards.first).markerY - XCTUnwrap(model.layout.nowY)
        XCTAssertEqual(before - after, TTTimeline.pointsPerMinute, accuracy: 0.001)
        XCTAssertEqual(model.cards(formatter)[0].relativeTime, "in 10 min")
    }

    func testCancelledTrainIsNeverTheNext() async throws {
        let cards = try await ScheduleViewModel.loadedFixture(.cancelled).cards(formatter)
        XCTAssertEqual(cards[0].status, .cancelled)
        XCTAssertFalse(cards[0].isNext)
        XCTAssertTrue(cards[1].isNext, "The next valid train becomes the lead")
    }

    // MARK: TT-114 delayed and cancelled

    /// delayedScenario: the 7:32 AM card sits at 7:41 AM, the bar is 9 min long, and the train keeps its name.
    func testDelayedTrainSitsAtItsExpectedTimeAndKeepsItsName() async throws {
        let model = try await ScheduleViewModel.loadedFixture(.delayed)
        let card = try XCTUnwrap(model.cards(formatter).first)
        XCTAssertEqual(card.id.tripId, "LW-0732-20261105")
        XCTAssertTrue(card.isNext)
        XCTAssertEqual(card.time, "7:41 AM", "Only the expected time; the scheduled one is in Trip details (D50)")
        XCTAssertEqual(card.status, .delayed(minutes: 9))
        XCTAssertTrue(card.isDelayed)
        XCTAssertEqual(card.arrivalTime, "8:21 AM")
        XCTAssertEqual(card.tripLength, "40 min", "Arrival minus departure of the shown times")
        XCTAssertEqual(card.relativeTime, "in 20 min")
        XCTAssertFalse(card.isCancelled)

        let place = try XCTUnwrap(model.layout.cards.first { $0.id == card.id })
        let bar = try XCTUnwrap(place.delayBar)
        let nowY = try XCTUnwrap(model.layout.nowY)
        XCTAssertEqual(bar.upperBound - bar.lowerBound, 9 * TTTimeline.pointsPerMinute, accuracy: 0.001)
        XCTAssertEqual(place.markerY - nowY, 20 * TTTimeline.pointsPerMinute, accuracy: 0.001)
        XCTAssertFalse(model.cards(formatter)[1].isDelayed)
    }

    /// The clock passing the scheduled time is not evidence of departure: the delayed train stays the lead.
    func testDelayedTrainStaysTheLeadPastItsScheduledTime() async throws {
        let repository = try FixtureScheduleRepository(scenario: .delayed, bundle: Bundle(for: TimelineCardsTests.self))
        let clock = TestClock(now: repository.now)
        let model = ScheduleViewModel(route: repository.route, repository: repository, clock: clock)
        await model.loadIfNeeded()
        clock.advance(minutes: 14) // 7:35 AM
        model.tick()
        XCTAssertEqual(model.nextDepartureId?.tripId, "LW-0732-20261105")
        let card = try XCTUnwrap(model.cards(formatter).first)
        XCTAssertEqual(card.relativeTime, "in 6 min")
        XCTAssertNotNil(model.layout.cards.first?.delayBar)
    }

    /// cancelledScenario: struck red marker, no bell, "Next usable below", and the next valid train leads.
    func testCancelledCardKeepsItsSlotAndPointsBelow() async throws {
        let model = try await ScheduleViewModel.loadedFixture(.cancelled)
        let cards = model.cards(formatter)
        let cancelled = cards[0]
        XCTAssertTrue(cancelled.isCancelled)
        XCTAssertEqual(cancelled.time, "7:32 AM", "Keeps its scheduled slot")
        XCTAssertFalse(cancelled.isNext)
        XCTAssertEqual(cancelled.note, "Next usable below")
        XCTAssertNil(cancelled.relativeTime)
        XCTAssertTrue(cards[1].isNext)
        XCTAssertNil(cards[1].note)
        let place = try XCTUnwrap(model.layout.cards.first)
        let nowY = try XCTUnwrap(model.layout.nowY)
        XCTAssertNil(place.delayBar)
        XCTAssertEqual(place.markerY - nowY, 11 * TTTimeline.pointsPerMinute, accuracy: 0.001)
    }

    /// The evening fixture: a cancelled train between two usable ones (schedule-dark.png).
    func testCancelledTrainBetweenUsableTrains() async throws {
        let cards = try await ScheduleViewModel.loadedFixture(.eveningDark).cards(formatter)
        XCTAssertEqual(cards.map(\.time), ["5:10 PM", "5:28 PM", "5:52 PM", "6:40 PM"])
        XCTAssertEqual(cards.map(\.isNext), [true, false, false, false])
        XCTAssertEqual(cards.map(\.isCancelled), [false, true, false, false])
        XCTAssertEqual(cards[1].note, "Next usable below")
    }

    func testAnotherDayHasNoNextTrainAndScheduledOnly() async throws {
        let repository = try FixtureScheduleRepository(bundle: Bundle(for: TimelineCardsTests.self))
        let wednesday = repository.now.addingTimeInterval(-24 * 60 * 60)
        let model = ScheduleViewModel(route: repository.route, repository: repository, clock: FixedClock(now: wednesday))
        await model.loadIfNeeded()
        await model.select(model.days[1]) // Thu Nov 5, the fixture day
        let cards = model.cards(formatter)
        XCTAssertEqual(cards.count, 4)
        XCTAssertNil(model.nextDepartureId)
        XCTAssertTrue(cards.allSatisfy { !$0.isNext && $0.relativeTime == nil && $0.status == .scheduled })
    }

    func testTimesFollowTheTimeFormat() async throws {
        let card = try await ScheduleViewModel.loadedFixture().cards(TimeFormatter(format: .twentyFourHour))[0]
        XCTAssertEqual(card.time, "07:32")
        XCTAssertEqual(card.arrivalTime, "08:12")
    }

    /// The view reports measured cards; the time line stays centred on the marker.
    func testMeasuredCardSizeFeedsTheLayout() async throws {
        let model = try await ScheduleViewModel.loadedFixture()
        let id = try XCTUnwrap(model.nextDepartureId)
        model.setCardSize(TimelineCardSize(height: 122, anchor: 35), for: id)
        let card = try XCTUnwrap(model.layout.cards.first { $0.id == id })
        XCTAssertEqual(card.markerY - card.top, 35, accuracy: 0.001)
        XCTAssertEqual(card.bottom - card.top, 122, accuracy: 0.001)
    }

    /// A gridline label hides near the "Now" label; the line itself stays (D49).
    func testGridlineLabelHidesNearNow() async throws {
        let model = try await ScheduleViewModel.loadedFixture(minutesLater: 25) // 7:46 AM
        let day = model.selectedDay
        let quarterTo = try XCTUnwrap(model.layout.gridlines.first { $0.time == day.date(hour: 7, minute: 45) })
        XCTAssertFalse(model.showsLabel(quarterTo), "Now is 1 min below it")
        let quarterPast = try XCTUnwrap(model.layout.gridlines.first { $0.time == day.date(hour: 8, minute: 15) })
        XCTAssertTrue(model.showsLabel(quarterPast))
    }

    /// The left column holds gridline times only, every 15 min, and no train times (D49).
    func testGridlinesRunEveryFifteenMinutes() async throws {
        let model = try await ScheduleViewModel.loadedFixture()
        let day = model.selectedDay
        let minutes = model.layout.gridlines.map { Calendar.current.dateComponents(in: goTimeZone, from: $0.time).minute }
        XCTAssertTrue(minutes.allSatisfy { [0, 15, 30, 45].contains($0 ?? -1) })
        let half = try XCTUnwrap(model.layout.gridlines.first { $0.time == day.date(hour: 8, minute: 30) })
        let quarter = try XCTUnwrap(model.layout.gridlines.first { $0.time == day.date(hour: 8, minute: 45) })
        XCTAssertEqual(quarter.y - half.y, 15 * TTTimeline.pointsPerMinute, accuracy: 0.001)
    }
}
