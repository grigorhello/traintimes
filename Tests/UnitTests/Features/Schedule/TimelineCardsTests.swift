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
        XCTAssertEqual(next.pillTime, "7:32")
        XCTAssertEqual(next.relativeTime, "in 11 min")
        XCTAssertEqual(next.status, .onTime)
        XCTAssertEqual(next.arrivalLabel, "Scheduled arrival")
        XCTAssertEqual(next.arrivalTime, "8:12 AM")
        XCTAssertEqual(next.platform, "Platform 2")

        XCTAssertNil(cards[1].relativeTime, "No other card shows a relative time")
        XCTAssertEqual(cards[1].platform, "Platform pending")
        XCTAssertEqual(cards[1].tags, [.express], "Only verified tags; the canvas's Bike coach is a placeholder")
        XCTAssertEqual(cards[2].status, .scheduled, "No live data for this trip: Scheduled, never On time")
    }

    func testNextTrainMovesOnOnceItsTimePasses() async throws {
        let model = try await ScheduleViewModel.loadedFixture(minutesLater: 12) // 7:33 AM
        let cards = model.cards(formatter)
        XCTAssertEqual(model.nextDepartureId?.tripId, "LW-0758-20261105")
        XCTAssertEqual(cards[1].relativeTime, "in 25 min")
        XCTAssertFalse(cards[0].isNext, "7:32 AM has left")
    }

    func testCancelledTrainIsNeverTheNext() async throws {
        let cards = try await ScheduleViewModel.loadedFixture(.cancelled).cards(formatter)
        XCTAssertEqual(cards[0].status, .cancelled)
        XCTAssertFalse(cards[0].isNext)
        XCTAssertTrue(cards[1].isNext, "The next valid train becomes the lead")
    }

    func testAnotherDayHasNoNextTrainAndScheduledBadgesOnly() async throws {
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
        XCTAssertEqual(card.pillTime, "07:32")
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

    /// A gridline label hides near the "Now" label as well as near a pill; the line itself stays.
    func testGridlineLabelHidesNearNow() async throws {
        let model = try await ScheduleViewModel.loadedFixture(minutesLater: 25) // 7:46 AM
        let day = model.selectedDay
        let quarterTo = try XCTUnwrap(model.layout.gridlines.first { $0.time == day.date(hour: 7, minute: 45) })
        XCTAssertTrue(quarterTo.showsLabel, "No pill near 7:45")
        XCTAssertFalse(model.showsLabel(quarterTo), "Now is 1 min below it")
        let quarterPast = try XCTUnwrap(model.layout.gridlines.first { $0.time == day.date(hour: 8, minute: 15) })
        XCTAssertTrue(model.showsLabel(quarterPast))
    }
}
