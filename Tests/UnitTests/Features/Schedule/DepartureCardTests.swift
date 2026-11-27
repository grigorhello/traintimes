import XCTest
@testable import TrainTimes

/// TT-157: what the three-row card shows (D50): trip length, platform slot, status dot and Express bolt.
final class DepartureCardTests: XCTestCase {
    private let formatter = TimeFormatter(format: .twelveHour)
    private let day = ServiceDay(year: 2026, month: 11, day: 5)

    private func card(
        minutes: Int = 40, platform: Platform = .pending, tags: [TrainTag] = [], status: TrainStatus = .scheduled,
        isDeparted: Bool = false, isBoarding: Bool = false, isNext: Bool = false, minutesBefore: Int = 0
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
        return DepartureCard(
            resolved, isNext: isNext, isDeparted: isDeparted, isBoarding: isBoarding,
            now: departure.addingTimeInterval(TimeInterval(-minutesBefore * 60)), formatter: formatter
        )
    }

    /// TT-246 (D123) revises D81: minutes up to 59, then hours, as every count of minutes reads.
    func testTripLengthInMinutesUpTo59ThenHours() {
        let start = day.date(hour: 12, minute: 47)
        func length(_ minutes: Int) -> String {
            formatter.tripLength(from: start, to: start.addingTimeInterval(TimeInterval(minutes * 60)))
        }
        XCTAssertEqual(length(40), "40 min ride")
        XCTAssertEqual(length(59), "59 min ride")
        XCTAssertEqual(length(60), "1 h ride")
        XCTAssertEqual(length(72), "1 h 12 min ride")
        XCTAssertEqual(length(99), "1 h 39 min ride")
        XCTAssertEqual(length(100), "1 h 40 min ride")
        XCTAssertEqual(length(105), "1 h 45 min ride")
        XCTAssertEqual(length(120), "2 h ride")
        XCTAssertEqual(card(minutes: 72).tripLength, "1 h 12 min ride")
    }

    func testPlatformSlotIsAlwaysThere() {
        let published = card(platform: .published("26"))
        XCTAssertEqual(published.platformValue, "26")
        XCTAssertTrue(published.hasPlatform)
        let pending = card(platform: .pending)
        XCTAssertEqual(pending.platformValue, "—")
        XCTAssertFalse(pending.hasPlatform)
    }

    /// TT-248 (D125): the next train's countdown shows only beside a posted platform number, never beside the dash.
    func testCountdownWaitsForThePlatformNumber() {
        XCTAssertEqual(card(platform: .published("7"), isNext: true, minutesBefore: 11).relativeTime, "in 11 min")
        XCTAssertNil(card(platform: .pending, isNext: true, minutesBefore: 11).relativeTime)
        XCTAssertNil(card(platform: .published("7"), minutesBefore: 11).relativeTime, "Only the next train counts down")
    }

    /// TT-233 (D114): "Boarding" while the train stands at its platform, a late train too; "Departed" once it has left; a
    /// cancelled train keeps "Cancelled".
    func testTheStatusRowSaysBoardingThenDeparted() {
        XCTAssertEqual(card(status: .onTime).shownStatus, .onTime)
        XCTAssertEqual(card(status: .onTime, isBoarding: true).shownStatus, .boarding)
        XCTAssertEqual(card(status: .onTime, isBoarding: true).status, .onTime, "The train's own status stays under it")
        let late = card(status: .delayed(minutes: 9, reportedAt: day.date(hour: 7, minute: 50)), isBoarding: true)
        XCTAssertEqual(late.shownStatus, .boarding)
        XCTAssertTrue(late.isDelayed, "A late train's times stay amber while it boards")
        XCTAssertEqual(card(status: .onTime, isDeparted: true).shownStatus, .departed)
        XCTAssertEqual(card(status: .onTime, isDeparted: true, isBoarding: true).shownStatus, .departed, "Departed wins")
        let cancelled = card(status: .cancelled(reportedAt: day.date(hour: 7, minute: 5)), isDeparted: true)
        XCTAssertEqual(cancelled.shownStatus, .cancelled)
    }

    func testFilledDotForLiveStatusRingForScheduled() {
        XCTAssertTrue([TripStatus.onTime, .delayed(minutes: 9), .cancelled, .stopSkipped, .boarding].allSatisfy(\.isLive))
        XCTAssertFalse([TripStatus.scheduled, .lastReported(time: "7:29 AM"), .offline].contains(where: \.isLive))
        XCTAssertEqual(card(status: .scheduled).status, .scheduled, "No live data is never On time (D50)")
        XCTAssertEqual(card(status: .onTime).status, .onTime)
        XCTAssertEqual(card(status: .stale(lastReported: day.date(hour: 7, minute: 20))).status, .scheduled, "The status row says Last reported")
        XCTAssertEqual(card(status: .offline).status, .scheduled)
    }

    func testExpressFlagComesFromTheTrip() {
        XCTAssertTrue(card(tags: [.express]).isExpress)
        XCTAssertFalse(card().isExpress)
    }
}
