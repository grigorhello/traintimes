import XCTest

final class ScheduleTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Selecting Sun 8, then tapping the Schedule tab again, returns to Today (D49: there is no Now button). The
    /// app runs on the fixture clock, Thu Nov 5, so tile 3 is Sun 8.
    @MainActor
    func testAnotherDayThenScheduleTabReturnsToNow() {
        let app = XCUIApplication.onFixtures()
        app.launchArguments += LaunchArguments.fixtureRoute
        app.launch()

        XCTAssertTrue(app.buttons["schedule.route"].waitForExistence(timeout: 10))
        let today = app.buttons["schedule.day.0"]
        let sunday = app.buttons["schedule.day.3"]
        XCTAssertTrue(today.isSelected)
        XCTAssertFalse(app.buttons["schedule.now"].exists, "No Now button anywhere")

        sunday.tap()
        // The fixtures run no trains on Sunday, so the empty state shows once the day has switched.
        XCTAssertTrue(app.buttons["emptyState.action"].waitForExistence(timeout: 5))
        XCTAssertTrue(sunday.isSelected)
        XCTAssertFalse(today.isSelected)

        app.tabBars.buttons["Schedule"].tap()
        let card = app.descendants(matching: .any).matching(identifier: "schedule.card.LW-0732-20261105").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue(today.isSelected)
        XCTAssertFalse(sunday.isSelected)
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

    /// The Notice chip on the line row opens the notice sheet; dismissing the notice closes the sheet and hides the
    /// link (TT-132).
    @MainActor
    func testLineNoticeOpensAndDismisses() {
        let app = XCUIApplication.onDelayedFixture()
        app.launchArguments += LaunchArguments.fixtureRoute + LaunchArguments.noDismissedNotices
        app.launch()

        let link = app.buttons["schedule.lineNotice"]
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        link.tap()
        let sheet = app.descendants(matching: .any).matching(identifier: "sheet.lineNotices").firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))

        app.buttons["notice.dismiss"].tap()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))
        XCTAssertFalse(link.exists)
    }
}
