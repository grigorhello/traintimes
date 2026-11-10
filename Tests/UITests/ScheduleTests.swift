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

    /// TT-160: the strip opens at Today, the past week is a swipe to the right, and yesterday opens like any other day.
    @MainActor
    func testStripOpensAtTodayAndYesterdayIsASwipeAway() {
        let app = XCUIApplication.onFixtures()
        app.launchArguments += LaunchArguments.fixtureRoute
        app.launch()

        let today = app.buttons["schedule.day.0"]
        let yesterday = app.buttons["schedule.day.-1"]
        XCTAssertTrue(today.waitForExistence(timeout: 10))
        XCTAssertTrue(today.isHittable, "The strip opens with Today first")
        // Yesterday's tile peeks into the leading margin (like the sixth tile at the right edge), its middle out of view.
        XCTAssertTrue(yesterday.exists)
        XCTAssertLessThan(yesterday.frame.midX, 0, "The past week is out of view to the left")

        today.swipeRight()
        XCTAssertTrue(yesterday.waitForExistence(timeout: 5))
        yesterday.tap()
        XCTAssertTrue(yesterday.isSelected)
        XCTAssertFalse(today.isSelected)

        app.tabBars.buttons["Schedule"].tap()
        let back = expectation(for: NSPredicate(format: "isSelected == true && isHittable == true"), evaluatedWith: today)
        XCTAssertEqual(XCTWaiter().wait(for: [back], timeout: 5), .completed, "The tab re-tap returns to Today, with the strip")
        XCTAssertFalse(yesterday.isSelected)
    }

    /// Tapping a card opens Trip details for that train (TT-113, TT-118, TT-163); Close returns to the timetable.
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
        let last = app.descendants(matching: .any).matching(identifier: "trip.stop.UN").firstMatch
        XCTAssertTrue(last.waitForExistence(timeout: 5))
        let alert = app.buttons["trip.alert"]
        XCTAssertTrue(alert.exists)

        // The whole list is reachable: scroll to the last stop, which then sits above the floating button (TT-163).
        if !last.isHittable { sheet.swipeUp() }
        XCTAssertTrue(last.isHittable)
        XCTAssertLessThanOrEqual(last.frame.maxY, alert.frame.minY)

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
