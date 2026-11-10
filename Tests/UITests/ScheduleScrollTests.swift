import XCTest

/// TT-159 (D52): the timeline opens scrolled to Now on a day as long as a real one, and the screen turns to the next day
/// at midnight. Runs on the full-day fixture with Mock time (TT-158), which puts Now anywhere in it.
final class ScheduleScrollTests: XCTestCase {
    /// Thu Nov 5 2026, Toronto: 5:47 PM, 11:45 PM and 11:59:35 PM, in seconds since 1970 (EST, UTC-5).
    private enum Moment {
        static let evening = 1_793_918_820
        static let late = 1_793_940_300
        static let almostMidnight = 1_793_941_175
    }

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(mockTime: Int) -> XCUIApplication {
        let app = XCUIApplication.onFullDayFixture()
        // Mock time set by hand on this simulator would leave a "set at" moment that skews the clock: zero it.
        app.launchArguments += LaunchArguments.fixtureRoute + ["-settings.mockTime", "\(mockTime)", "-settings.mockTimeSetAt", "0"]
        app.launch()
        return app
    }

    @MainActor
    private func card(_ app: XCUIApplication, _ time: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "schedule.card.LW-\(time)-20261105").firstMatch
    }

    @MainActor
    private func waitUntilHittable(_ app: XCUIApplication, _ element: XCUIElement, _ message: String, timeout: TimeInterval = 15) {
        let done = expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: element)
        let result = XCTWaiter().wait(for: [done], timeout: timeout)
        XCTAssertEqual(result, .completed, "\(message). \(whereTheCardsAre(app))")
    }

    /// Frames of the header and some cards, in the failure message: CI shows no screenshots, so this says where the
    /// timeline stopped.
    @MainActor
    private func whereTheCardsAre(_ app: XCUIApplication) -> String {
        func frame(_ element: XCUIElement) -> String {
            element.exists ? "\(element.frame) hittable=\(element.isHittable)" : "missing"
        }
        let cards = ["0524", "1724", "1754", "2324"].map { "\($0) \(frame(card(app, $0)))" }.joined(separator: "; ")
        return "app \(app.frame); route card \(frame(app.buttons["schedule.from"])); \(cards)"
    }

    /// 5:47 PM: the 5:54 PM train is the next one and sits near the top; the 5:24 AM train, hours gone, is off screen.
    @MainActor
    func testOpensScrolledToNowNotAtTheFirstTrain() {
        let app = launch(mockTime: Moment.evening)
        let next = card(app, "1754")
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        waitUntilHittable(app, next, "The timeline scrolls to the next train")
        XCTAssertLessThan(next.frame.minY, app.frame.height * 0.6, "The next train is in the upper part of the screen")
        XCTAssertFalse(card(app, "0524").isHittable, "The first train of the morning is scrolled away")
    }

    /// 11:45 PM, after the last train: the timeline ends on that train, not on the first one.
    @MainActor
    func testLateAtNightOpensAtTheEndOfTheDay() {
        let app = launch(mockTime: Moment.late)
        let last = card(app, "2324")
        XCTAssertTrue(last.waitForExistence(timeout: 10))
        waitUntilHittable(app, last, "The timeline scrolls to the end of the service day")
        XCTAssertFalse(card(app, "0524").isHittable)
    }

    /// 11:59:35 PM Thursday: Today is the 5th. A minute later Today is the 6th, selected, with its timeline from the top.
    @MainActor
    func testTheDayTurnsAtMidnightAndShowsTheNewDayFromTheTop() {
        let app = launch(mockTime: Moment.almostMidnight)
        let today = app.buttons["schedule.day.0"]
        XCTAssertTrue(today.waitForExistence(timeout: 10))
        XCTAssertTrue(today.isSelected)
        XCTAssertTrue(today.label.contains("5"), "Today is Nov 5: \(today.label)")

        let turned = expectation(for: NSPredicate(format: "label CONTAINS '6'"), evaluatedWith: today)
        XCTAssertEqual(XCTWaiter().wait(for: [turned], timeout: 90), .completed, "The strip's Today becomes Nov 6")
        XCTAssertTrue(today.isSelected)
        waitUntilHittable(app, card(app, "0524"), "The new day starts from its top: the first train is on screen")
    }
}
