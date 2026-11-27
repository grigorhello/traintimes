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
        XCTAssertEqual(AlertDays.week.map(AlertDays.letter), ["M", "T", "W", "T", "F", "S", "S"])
        XCTAssertEqual(AlertDays.fullName(7), "Sunday")
    }

    /// Trip details' day marks (TT-254): a repeating alert's day lights or clears, and its last lit day stays lit.
    func testADayMarkLightsOrClearsARepeatingAlertsDay() {
        XCTAssertEqual(AlertDays.toggled(6, in: [1, 2, 3, 4, 5], ownDay: 4), [1, 2, 3, 4, 5, 6], "lit")
        XCTAssertEqual(AlertDays.toggled(2, in: [1, 2, 3, 4, 5], ownDay: 4), [1, 3, 4, 5], "cleared")
        XCTAssertEqual(AlertDays.toggled(4, in: [4, 1], ownDay: 4), [1], "its own day clears like any other")
        XCTAssertEqual(AlertDays.toggled(3, in: [3], ownDay: 4), [3], "the last lit day stays lit")
    }

    /// The one-day rule (TT-254): lighting any day makes a one-day alert repeat and keeps its own day; the ring itself
    /// makes it repeat on that day alone.
    func testLightingAnyDayMakesAOneDayAlertRepeatAndKeepsItsOwnDay() {
        XCTAssertEqual(AlertDays.toggled(1, in: [], ownDay: 4), [1, 4])
        XCTAssertEqual(AlertDays.toggled(6, in: [], ownDay: 4), [4, 6])
        XCTAssertEqual(AlertDays.toggled(4, in: [], ownDay: 4), [4], "the ring")
    }
}
