import XCTest
@testable import TrainTimes

/// Before departure's window (TT-177, D69): live from 30 min before the expected departure, Boarding now from 2 min before,
/// Departed for 2 min, then over; cancelled trains never; of the alerted trains, the one that leaves first.
final class LiveDepartureTests: XCTestCase {
    private let day = ServiceDay(year: 2026, month: 11, day: 5)

    private func departure(
        _ id: String, at hour: Int, _ minute: Int, status: TrainStatus = .onTime, delay: Int = 0, platform: Platform = .pending
    ) -> Departure {
        let scheduled = day.date(hour: hour, minute: minute)
        let expected = scheduled.addingTimeInterval(TimeInterval(delay * 60))
        let hasEstimate = switch status {
        case .onTime, .delayed: true
        default: false
        }
        return Departure(
            trip: Trip(
                key: TripKey(serviceDay: day, tripId: id), scheduledDeparture: scheduled,
                scheduledArrival: scheduled.addingTimeInterval(30 * 60), platform: platform, tags: []
            ),
            status: status,
            expectedDeparture: hasEstimate ? expected : nil,
            expectedArrival: hasEstimate ? expected.addingTimeInterval(30 * 60) : nil
        )
    }

    private func at(_ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        day.date(hour: hour, minute: minute).addingTimeInterval(TimeInterval(second))
    }

    func testTheWindowOpens30MinBeforeTheTrainLeaves() {
        let train = departure("A", at: 17, 13)
        XCTAssertNil(LiveDeparture(train, now: at(16, 42, 59)))
        XCTAssertEqual(LiveDeparture(train, now: at(16, 43))?.phase, .countingDown)
        XCTAssertEqual(LiveDeparture(train, now: at(16, 43))?.minutes(at: at(16, 43)), 30)
    }

    func testBoardingFor2MinThenDepartedFor2MinThenOver() {
        let train = departure("A", at: 17, 13)
        XCTAssertEqual(LiveDeparture(train, now: at(17, 10, 59))?.phase, .countingDown)
        XCTAssertEqual(LiveDeparture(train, now: at(17, 11))?.phase, .boarding)
        XCTAssertEqual(LiveDeparture(train, now: at(17, 12, 59))?.phase, .boarding)
        XCTAssertEqual(LiveDeparture(train, now: at(17, 13))?.phase, .departed)
        XCTAssertEqual(LiveDeparture(train, now: at(17, 14, 59))?.phase, .departed)
        XCTAssertNil(LiveDeparture(train, now: at(17, 15)))
    }

    func testALateTrainCountsToItsExpectedDeparture() throws {
        let train = departure("A", at: 17, 13, status: .delayed(minutes: 3, reportedAt: at(17, 4)), delay: 3)
        let live = try XCTUnwrap(LiveDeparture(train, now: at(17, 4)))
        XCTAssertEqual(live.phase, .countingDown)
        XCTAssertEqual(live.minutes(at: at(17, 4)), 12)
        XCTAssertEqual(live.delayMinutes, 3)
        XCTAssertEqual(LiveDeparture(train, now: at(17, 13))?.phase, .countingDown, "3 min to its late time")
        XCTAssertEqual(LiveDeparture(train, now: at(17, 14))?.phase, .boarding)
        XCTAssertEqual(LiveDeparture(train, now: at(17, 16))?.phase, .departed)
    }

    func testTheCountdownShowsWholeMinutesAndOneAtLeast() throws {
        let live = try XCTUnwrap(LiveDeparture(departure("A", at: 17, 13), now: at(17, 1)))
        XCTAssertEqual(live.minutes(at: at(17, 0, 30)), 12)
        XCTAssertEqual(live.minutes(at: at(17, 12, 30)), 1)
    }

    func testACancelledTrainNeverGoesLive() {
        XCTAssertNil(LiveDeparture(departure("A", at: 17, 13, status: .cancelled(reportedAt: at(17, 0))), now: at(17, 1)))
        XCTAssertNil(LiveDeparture(departure("A", at: 17, 13, status: .stopSkipped), now: at(17, 1)))
    }

    func testThePlatformAndLiveDataAreReadFromTheDeparture() throws {
        let posted = try XCTUnwrap(LiveDeparture(departure("A", at: 17, 13, platform: .published("7")), now: at(17, 1)))
        XCTAssertEqual(posted.platform, "7")
        XCTAssertTrue(posted.isLive)
        let timetable = try XCTUnwrap(LiveDeparture(departure("A", at: 17, 13, status: .scheduled), now: at(17, 1)))
        XCTAssertNil(timetable.platform)
        XCTAssertFalse(timetable.isLive)
    }

    func testTheAlertedTrainThatLeavesFirstWins() {
        let trains = [departure("A", at: 17, 13), departure("B", at: 17, 5), departure("C", at: 17, 20)]
        let now = at(17, 0)
        XCTAssertEqual(LiveDeparture.earliest(in: trains, now: now) { _ in true }?.key.tripId, "B")
        XCTAssertEqual(LiveDeparture.earliest(in: trains, now: now) { $0.trip.key.tripId != "B" }?.key.tripId, "A")
    }

    func testOnlyAlertedTrainsGoLive() {
        let trains = [departure("A", at: 17, 13), departure("B", at: 17, 5)]
        XCTAssertNil(LiveDeparture.earliest(in: trains, now: at(17, 0)) { _ in false })
    }

    func testAnAlertedTrainOutsideItsWindowLeavesItToTheNext() {
        // A has left more than 2 min ago; D is more than 30 min away; C is the live one.
        let trains = [departure("A", at: 16, 50), departure("C", at: 17, 20), departure("D", at: 17, 40)]
        XCTAssertEqual(LiveDeparture.earliest(in: trains, now: at(17, 0)) { _ in true }?.key.tripId, "C")
    }

    func testALateEarlierTrainLeavesAfterTheNextOneOnTime() {
        // A is scheduled first but 10 min late, so B leaves first and wins.
        let trains = [
            departure("A", at: 17, 5, status: .delayed(minutes: 10, reportedAt: at(17, 0)), delay: 10), departure("B", at: 17, 10),
        ]
        XCTAssertEqual(LiveDeparture.earliest(in: trains, now: at(17, 0)) { _ in true }?.key.tripId, "B")
    }
}
