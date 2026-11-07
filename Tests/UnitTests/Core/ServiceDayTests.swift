import XCTest
@testable import TrainTimes

final class ServiceDayTests: XCTestCase {
    private func utc(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    func testTripAfterMidnightBelongsToPreviousServiceDay() {
        let lateTrip = utc("2026-11-06T05:40:00Z") // 00:40 Toronto, Nov 6
        XCTAssertEqual(ServiceDay(containing: lateTrip), ServiceDay(year: 2026, month: 11, day: 5))
        XCTAssertEqual(ServiceDay(containing: utc("2026-11-06T08:00:00Z")).description, "2026-11-06") // 3:00 AM
    }

    func testTripAt0040SortsAfter2359() {
        let lastEvening = utc("2026-11-06T04:59:00Z") // 23:59 Nov 5
        let afterMidnight = utc("2026-11-06T05:40:00Z") // 00:40 Nov 6
        let morning = utc("2026-11-05T12:32:00Z") // 07:32 Nov 5
        XCTAssertEqual(ServiceDay.minutesIntoServiceDay(lastEvening), 1439)
        XCTAssertEqual(ServiceDay.minutesIntoServiceDay(afterMidnight), 1480)

        let sorted = [afterMidnight, lastEvening, morning].sorted {
            ServiceDay.minutesIntoServiceDay($0) < ServiceDay.minutesIntoServiceDay($1)
        }
        XCTAssertEqual(sorted, [morning, lastEvening, afterMidnight])
        XCTAssertEqual(ServiceDay(containing: afterMidnight), ServiceDay(containing: lastEvening))
    }

    func testServiceDayAcrossDSTChanges() {
        // Spring forward 2026-03-08: 1:30 AM EST is still March 7's service day.
        XCTAssertEqual(ServiceDay(containing: utc("2026-03-08T06:30:00Z")).description, "2026-03-07")
        XCTAssertEqual(ServiceDay(containing: utc("2026-03-08T07:00:00Z")).description, "2026-03-08") // 3:00 AM EDT
        // Fall back 2026-11-01: both 1:30 AMs belong to October 31.
        XCTAssertEqual(ServiceDay(containing: utc("2026-11-01T05:30:00Z")).description, "2026-10-31")
        XCTAssertEqual(ServiceDay(containing: utc("2026-11-01T06:30:00Z")).description, "2026-10-31")
    }

    func testServiceDaysOrderAcrossMonthAndYear() {
        XCTAssertEqual(ServiceDay(containing: utc("2027-01-01T06:00:00Z")).description, "2026-12-31")
        XCTAssertLessThan(ServiceDay(year: 2026, month: 12, day: 31), ServiceDay(year: 2027, month: 1, day: 1))
    }

    func testDayStripLabels() {
        let thursday = ServiceDay(year: 2026, month: 11, day: 5)
        XCTAssertEqual(thursday.weekdayShort, "Thu")
        XCTAssertEqual(thursday.adding(days: 3).weekdayShort, "Sun")
        XCTAssertEqual(thursday.adding(days: 3).shortLabel, "Sun, Nov 8")
        XCTAssertEqual(ServiceDay(year: 2026, month: 12, day: 31).adding(days: 1), ServiceDay(year: 2027, month: 1, day: 1))
        // Fall back on Nov 1 does not skip or repeat a day.
        XCTAssertEqual(ServiceDay(year: 2026, month: 10, day: 31).adding(days: 2), ServiceDay(year: 2026, month: 11, day: 2))
    }
}
