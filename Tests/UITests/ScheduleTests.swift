import XCTest

final class ScheduleTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Selecting Sun 8 then tapping Today returns to today and now in one tap (TT-112). The app runs on the fixture
    /// clock, Thu Nov 5, so cell 3 is Sun 8.
    @MainActor
    func testAnotherDayThenTodayReturnsToNow() {
        let app = XCUIApplication.onFixtures()
        app.launchArguments += LaunchArguments.fixtureRoute
        app.launch()

        XCTAssertTrue(app.buttons["schedule.route"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Updated just now"].waitForExistence(timeout: 5))
        let today = app.buttons["schedule.day.0"]
        let sunday = app.buttons["schedule.day.3"]
        let now = app.buttons["schedule.now"]
        XCTAssertTrue(today.isSelected)
        XCTAssertEqual(now.label, "Back to now, today")

        sunday.tap()
        XCTAssertTrue(app.staticTexts["Scheduled times only · Sun, Nov 8"].waitForExistence(timeout: 5))
        XCTAssertTrue(sunday.isSelected)
        XCTAssertFalse(today.isSelected)
        XCTAssertEqual(now.label, "Back to today")

        now.tap()
        XCTAssertTrue(app.staticTexts["Updated just now"].waitForExistence(timeout: 5))
        XCTAssertTrue(today.isSelected)
        XCTAssertFalse(sunday.isSelected)
        XCTAssertEqual(now.label, "Back to now, today")
    }

    /// Tapping a card opens Trip details for that train (TT-113, TT-118); Close returns to the timetable.
    @MainActor
    func testTapCardOpensTripDetails() {
        let app = XCUIApplication.onFixtures()
        app.launchArguments += LaunchArguments.fixtureRoute
        app.launch()

        let card = app.descendants(matching: .any).matching(identifier: "schedule.card.LW-0732-20261105").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()
        let sheet = app.descendants(matching: .any).matching(identifier: "sheet.tripDetails").firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "trip.stop.UN").firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["trip.alert"].exists)

        app.buttons["trip.close"].tap()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))
        XCTAssertTrue(card.exists)
    }
}
