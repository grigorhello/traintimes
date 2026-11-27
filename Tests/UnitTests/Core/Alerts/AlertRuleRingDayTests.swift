import XCTest
@testable import TrainTimes

/// The day Pick a new train opens Schedule on (TT-255, D129): the next day the alert rings, Today while its old time is
/// still ahead. Thu Nov 5, the 7:32 AM train.
final class AlertRuleRingDayTests: XCTestCase {
    private let thursday = ServiceDay(year: 2026, month: 11, day: 5)
    private let route = Route(
        from: Station(id: "OA", name: "Oakville"), to: Station(id: "UN", name: "Union"),
        line: Line(id: "LW", name: "Lakeshore West", colorHex: nil)
    )

    private func rule(_ kind: AlertRule.Kind, on day: ServiceDay? = nil, weekdays: [Int] = []) -> AlertRule {
        let day = day ?? thursday
        let departure = day.date(hour: 7, minute: 32)
        let trip = Trip(
            key: TripKey(serviceDay: day, tripId: "LW-0732"), scheduledDeparture: departure,
            scheduledArrival: departure.addingTimeInterval(40 * 60), platform: .pending, tags: []
        )
        return AlertRule(kind: kind, trip: trip, route: route, weekdays: weekdays)
    }

    func testARepeatingAlertRingsTodayWhileItsTimeIsAhead() {
        let weekdays = rule(.repeating, weekdays: [1, 2, 3, 4, 5])
        XCTAssertEqual(weekdays.nextRingDay(today: thursday, now: thursday.date(hour: 7, minute: 0)), thursday)
        XCTAssertEqual(
            weekdays.nextRingDay(today: thursday, now: thursday.date(hour: 9, minute: 0)), thursday.adding(days: 1),
            "Past its time today: Friday"
        )
        let fridays = rule(.repeating, weekdays: [5])
        XCTAssertEqual(fridays.nextRingDay(today: thursday, now: thursday.date(hour: 7, minute: 0)), thursday.adding(days: 1))
        let mondays = rule(.repeating, weekdays: [1])
        XCTAssertEqual(mondays.nextRingDay(today: thursday, now: thursday.date(hour: 9, minute: 0)), thursday.adding(days: 4))
    }

    func testAOneDayAlertRingsOnItsOwnDay() {
        let saturday = thursday.adding(days: 2)
        XCTAssertEqual(rule(.thisTrip, on: saturday).nextRingDay(today: thursday, now: thursday.date(hour: 9, minute: 0)), saturday)
        let tuesday = thursday.adding(days: -2)
        XCTAssertEqual(
            rule(.thisTrip, on: tuesday).nextRingDay(today: thursday, now: thursday.date(hour: 9, minute: 0)), thursday,
            "Its day has passed: Today"
        )
    }
}
