import XCTest
@testable import TrainTimes

/// A repeating alert's days in words, and the days Repeat starts with (TT-191).
final class AlertDaysTests: XCTestCase {
    func testSummary() {
        XCTAssertEqual(AlertDays.summary(of: [1, 2, 3, 4, 5]), "Mon to Fri")
        XCTAssertEqual(AlertDays.summary(of: [5, 3, 4]), "Wed to Fri")
        XCTAssertEqual(AlertDays.summary(of: [6, 7]), "Sat and Sun")
        XCTAssertEqual(AlertDays.summary(of: [1, 3, 5]), "Mon, Wed, Fri")
        XCTAssertEqual(AlertDays.summary(of: [3]), "Wed")
        XCTAssertEqual(AlertDays.summary(of: Array(1...7)), "Every day")
        XCTAssertNil(AlertDays.summary(of: []))
    }

    func testRepeatStartsMonToFriOrWithTheWeekendDay() {
        XCTAssertEqual(AlertDays.repeatDays(for: ServiceDay(year: 2026, month: 11, day: 5)), [1, 2, 3, 4, 5], "Thursday")
        XCTAssertEqual(AlertDays.repeatDays(for: ServiceDay(year: 2026, month: 11, day: 7)), [6], "Saturday")
        XCTAssertEqual(AlertDays.repeatDays(for: ServiceDay(year: 2026, month: 11, day: 8)), [7], "Sunday")
    }

    func testDayNames() {
        XCTAssertEqual(AlertDays.week.map(AlertDays.shortName), ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"])
        XCTAssertEqual(AlertDays.fullName(7), "Sunday")
    }
}
