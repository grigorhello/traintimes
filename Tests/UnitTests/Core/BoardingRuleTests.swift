import XCTest
@testable import TrainTimes

/// Boarding at the platform (TT-233, D114): Boarding while the train feed places the train at the station with its platform
/// posted, Departed when it moves off or the feed drops the station, the clock when no fresh position says anything.
final class BoardingRuleTests: XCTestCase {
    private let day = ServiceDay(year: 2026, month: 11, day: 5)

    private func at(_ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        day.date(hour: hour, minute: minute).addingTimeInterval(TimeInterval(second))
    }

    /// The 5:58 PM train, with what the feeds say about it at `seen`.
    private func train(
        status: TrainStatus = .onTime, delay: Int = 0, platform: Platform = .published("12"),
        metres: Double? = nil, seen: Date? = nil, hasLeftOrigin: Bool = false
    ) -> Departure {
        let scheduled = at(17, 58)
        let hasEstimate = switch status {
        case .onTime, .delayed: true
        default: false
        }
        return Departure(
            trip: Trip(
                key: TripKey(serviceDay: day, tripId: "A"), scheduledDeparture: scheduled,
                scheduledArrival: scheduled.addingTimeInterval(30 * 60), platform: platform, tags: []
            ),
            status: status,
            expectedDeparture: hasEstimate ? scheduled.addingTimeInterval(TimeInterval(delay * 60)) : nil,
            expectedArrival: nil,
            originFix: metres.map { OriginFix(metres: $0, reportedAt: seen ?? at(17, 50)) },
            hasLeftOrigin: hasLeftOrigin
        )
    }

    private func phase(_ departure: Departure, _ now: Date) -> BoardingRule.Phase {
        BoardingRule.phase(of: departure, now: now)
    }

    // MARK: Boarding

    func testATrainAtTheStationWithItsPlatformPostedIsBoarding() {
        XCTAssertEqual(phase(train(metres: 150, seen: at(17, 43)), at(17, 43, 20)), .boarding, "15 min before")
        XCTAssertEqual(phase(train(metres: 350, seen: at(17, 50)), at(17, 50, 5)), .boarding, "350 m is still at the station")
        XCTAssertTrue(train(metres: 150, seen: at(17, 50)).isBoarding(at: at(17, 50, 5)))
    }

    func testItStaysBoardingPastItsTimeWhileItStandsThere() {
        XCTAssertEqual(phase(train(metres: 120, seen: at(17, 58, 30)), at(17, 58, 40)), .boarding)
        XCTAssertEqual(phase(train(metres: 120, seen: at(18, 4)), at(18, 4, 10)), .boarding, "6 min past, still there")
        XCTAssertFalse(train(metres: 120, seen: at(18, 4)).hasLeft(at: at(18, 4, 10)))
    }

    func testWithNoPlatformPostedItIsNotBoardingAndNotDepartedWhileItStandsThere() {
        let waiting = train(platform: .pending, metres: 120, seen: at(17, 32))
        XCTAssertEqual(phase(waiting, at(17, 32, 10)), .waiting, "26 min before, at Union before its platform is posted")
        XCTAssertEqual(phase(train(platform: .pending, metres: 120, seen: at(17, 59)), at(17, 59, 10)), .waiting, "past its time")
    }

    func testALateTrainBoardsAgainstItsExpectedTime() {
        let reported = at(17, 50)
        let late = train(status: .delayed(minutes: 5, reportedAt: reported), delay: 5, metres: 140, seen: at(18, 1))
        XCTAssertEqual(phase(late, at(18, 1, 10)), .boarding)
        let away = train(status: .delayed(minutes: 5, reportedAt: reported), delay: 5, metres: 2_000, seen: at(18, 1))
        XCTAssertEqual(phase(away, at(18, 1, 10)), .waiting, "past the timetable, 2 min before its expected time, not here yet")
        XCTAssertEqual(phase(away, at(18, 3)), .departed(.moved))
    }

    // MARK: Departed

    func testItHasLeftWhenItsPositionIsAwayOnceItsTimeHasCome() {
        XCTAssertEqual(phase(train(metres: 351, seen: at(17, 58)), at(17, 58)), .departed(.moved))
        XCTAssertEqual(phase(train(metres: 900, seen: at(17, 58, 20)), at(17, 58, 30)), .departed(.moved))
        XCTAssertEqual(phase(train(metres: 900, seen: at(17, 58, 20)), at(17, 58, 30)).source, .moved)
    }

    func testAFarPositionInTheMinuteBeforeItsTimeIsATrainStillRollingIn() {
        XCTAssertEqual(phase(train(metres: 900, seen: at(17, 57, 20)), at(17, 57, 30)), .waiting)
        XCTAssertEqual(phase(train(metres: 900, seen: at(17, 40)), at(17, 40, 10)), .waiting)
    }

    func testTheFeedDroppingTheStationIsADepartureFromAMinuteBeforeItsTime() {
        XCTAssertEqual(phase(train(hasLeftOrigin: true), at(17, 56, 59)), .waiting, "too early to be this train leaving")
        XCTAssertEqual(phase(train(hasLeftOrigin: true), at(17, 57)), .departed(.feed))
        XCTAssertEqual(
            phase(train(metres: 200, seen: at(17, 58, 20), hasLeftOrigin: true), at(17, 58, 30)), .departed(.feed),
            "the feed comes first, though the position is still within 350 m"
        )
    }

    // MARK: The clock

    func testWithNoPositionItFollowsTheClock() {
        XCTAssertEqual(phase(train(), at(17, 57, 59)), .waiting)
        XCTAssertEqual(phase(train(), at(17, 58)), .departed(.clock))
        XCTAssertFalse(BoardingRule.hasSighting(of: train(), now: at(17, 50)))
    }

    func testAPositionOlderThan2MinSaysNothing() {
        let stale = train(metres: 120, seen: at(17, 50))
        XCTAssertEqual(phase(stale, at(17, 52)), .boarding, "2 min old")
        XCTAssertEqual(phase(stale, at(17, 52, 1)), .waiting, "never Boarding on a guess")
        XCTAssertFalse(BoardingRule.hasSighting(of: stale, now: at(17, 52, 1)))
        XCTAssertEqual(phase(train(metres: 120, seen: at(17, 57)), at(18, 8)), .departed(.clock), "10 min past with no fresh position")
        XCTAssertEqual(phase(train(metres: 900, seen: at(17, 55)), at(17, 58, 10)), .departed(.clock), "a stale far position is the clock")
    }

    func testCancelledAndSkippedTrainsNeverBoard() {
        let cancelled = train(status: .cancelled(reportedAt: at(17, 30)), metres: 120, seen: at(17, 50))
        XCTAssertEqual(phase(cancelled, at(17, 50, 10)), .waiting)
        XCTAssertEqual(phase(cancelled, at(17, 58)), .departed(.clock))
        let skipped = train(status: .stopSkipped, metres: 120, seen: at(17, 59))
        XCTAssertEqual(phase(skipped, at(17, 59, 10)), .departed(.clock), "standing there does not hold a skipped stop")
    }

    func testATimetableOnlyTrainBoardsOnItsPositionToo() {
        XCTAssertEqual(phase(train(status: .scheduled, metres: 120, seen: at(17, 50)), at(17, 50, 10)), .boarding)
    }
}
