import XCTest
@testable import TrainTimes

final class TimeFormatterTests: XCTestCase {
    private func utc(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    private func locale(hourCycle: Locale.HourCycle) -> Locale {
        var components = Locale.Components(identifier: "en_CA")
        components.hourCycle = hourCycle
        return Locale(components: components)
    }

    private let twelve = TimeFormatter(format: .twelveHour)
    private let twentyFour = TimeFormatter(format: .twentyFourHour)

    func testTwelveAndTwentyFourHourInToronto() {
        let morning = utc("2026-11-05T12:32:00Z") // 7:32 EST
        let evening = utc("2026-11-05T23:05:00Z") // 18:05 EST
        let afterMidnight = utc("2026-11-06T05:40:00Z") // 00:40 EST
        XCTAssertEqual(twelve.time(morning), "7:32 AM")
        XCTAssertEqual(twelve.time(evening), "6:05 PM")
        XCTAssertEqual(twelve.time(afterMidnight), "12:40 AM")
        XCTAssertEqual(twentyFour.time(morning), "07:32")
        XCTAssertEqual(twentyFour.time(evening), "18:05")
        XCTAssertEqual(twentyFour.time(afterMidnight), "00:40")
    }

    /// Time pills and gridline labels drop AM and PM (TT-113).
    func testRailTimeDropsTheDayPeriod() {
        let morning = utc("2026-11-05T12:32:00Z") // 7:32 EST
        let evening = utc("2026-11-05T23:05:00Z") // 18:05 EST
        XCTAssertEqual(twelve.railTime(morning), "7:32")
        XCTAssertEqual(twelve.railTime(evening), "6:05")
        XCTAssertEqual(twentyFour.railTime(morning), "07:32")
        XCTAssertEqual(twentyFour.railTime(evening), "18:05")
    }

    func testDeviceModeFollowsLocaleHourCycle() {
        let date = utc("2026-11-05T23:05:00Z")
        let device12 = TimeFormatter(format: .device, locale: locale(hourCycle: .oneToTwelve))
        let device24 = TimeFormatter(format: .device, locale: locale(hourCycle: .zeroToTwentyThree))
        XCTAssertEqual(device12.time(date), "6:05 PM")
        XCTAssertEqual(device24.time(date), "18:05")
    }

    func testSpringForwardDay() {
        // 2026-03-08: 1:59 AM EST is followed by 3:00 AM EDT.
        XCTAssertEqual(twentyFour.time(utc("2026-03-08T06:59:00Z")), "01:59")
        XCTAssertEqual(twentyFour.time(utc("2026-03-08T07:00:00Z")), "03:00")
        XCTAssertEqual(twelve.time(utc("2026-03-08T11:32:00Z")), "7:32 AM")
    }

    func testFallBackDay() {
        // 2026-11-01: 1:30 AM happens twice, first in EDT then in EST.
        XCTAssertEqual(twentyFour.time(utc("2026-11-01T05:30:00Z")), "01:30")
        XCTAssertEqual(twentyFour.time(utc("2026-11-01T06:30:00Z")), "01:30")
        XCTAssertEqual(twelve.time(utc("2026-11-01T12:32:00Z")), "7:32 AM")
    }

    func testRelativeNextTrain() {
        let now = utc("2026-11-05T12:21:00Z")
        XCTAssertEqual(twelve.relative(until: now.addingTimeInterval(11 * 60), now: now), "in 11 min")
        XCTAssertEqual(twelve.relative(until: now.addingTimeInterval(59), now: now), "Departing")
        XCTAssertEqual(twelve.relative(until: now.addingTimeInterval(-30), now: now), "Departing")
    }

    func testUpdatedLine() {
        let now = utc("2026-11-05T12:21:00Z")
        XCTAssertEqual(twelve.updated(at: now.addingTimeInterval(-20), now: now), "Updated just now")
        XCTAssertEqual(twelve.updated(at: now.addingTimeInterval(-4 * 60), now: now), "Updated 4 min ago")
    }

    func testTimeFeedsPercentAtStrings() {
        let text = String(format: String(localized: "alert.toast_on"), twelve.time(utc("2026-11-05T12:32:00Z")))
        XCTAssertEqual(text, "Alert on for the 7:32 AM train")
    }
}
