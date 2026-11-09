import XCTest
@testable import TrainTimes

/// TT-157: what the three-row card shows (D50): trip length, platform slot, status dot and Express bolt.
final class DepartureCardTests: XCTestCase {
    private let formatter = TimeFormatter(format: .twelveHour)
    private let day = ServiceDay(year: 2026, month: 11, day: 5)

    private func card(
        minutes: Int = 40, platform: Platform = .pending, tags: [TrainTag] = [], status: TrainStatus = .scheduled
    ) -> DepartureCard {
        let departure = day.date(hour: 7, minute: 58)
        let trip = Trip(
            key: TripKey(serviceDay: day, tripId: "LW-0758"),
            scheduledDeparture: departure,
            scheduledArrival: departure.addingTimeInterval(TimeInterval(minutes * 60)),
            platform: platform,
            tags: tags
        )
        let resolved = Departure(trip: trip, status: status, expectedDeparture: nil, expectedArrival: nil)
        return DepartureCard(resolved, isNext: false, now: departure, formatter: formatter)
    }

    func testTripLengthInMinutesUpTo99ThenHours() {
        let start = day.date(hour: 12, minute: 47)
        func length(_ minutes: Int) -> String {
            formatter.tripLength(from: start, to: start.addingTimeInterval(TimeInterval(minutes * 60)))
        }
        XCTAssertEqual(length(40), "40 min")
        XCTAssertEqual(length(72), "72 min")
        XCTAssertEqual(length(99), "99 min")
        XCTAssertEqual(length(100), "1 h 40 min")
        XCTAssertEqual(length(105), "1 h 45 min")
        XCTAssertEqual(length(120), "2 h")
        XCTAssertEqual(card(minutes: 72).tripLength, "72 min")
    }

    func testPlatformSlotIsAlwaysThere() {
        let published = card(platform: .published("26"))
        XCTAssertEqual(published.platform, "Plat 26")
        XCTAssertEqual(published.platformValue, "26")
        XCTAssertTrue(published.hasPlatform)
        let pending = card(platform: .pending)
        XCTAssertEqual(pending.platform, "Plat —")
        XCTAssertFalse(pending.hasPlatform)
    }

    func testFilledDotForLiveStatusRingForScheduled() {
        XCTAssertTrue([TripStatus.onTime, .delayed(minutes: 9), .cancelled, .stopSkipped].allSatisfy(\.isLive))
        XCTAssertFalse([TripStatus.scheduled, .lastReported(time: "7:29 AM"), .offline].contains(where: \.isLive))
        XCTAssertEqual(card(status: .scheduled).status, .scheduled, "No live data is never On time (D50)")
        XCTAssertEqual(card(status: .onTime).status, .onTime)
    }

    func testExpressFlagComesFromTheTrip() {
        XCTAssertTrue(card(tags: [.express]).isExpress)
        XCTAssertFalse(card().isExpress)
    }
}
