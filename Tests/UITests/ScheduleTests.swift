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

        XCTAssertTrue(app.buttons["schedule.from"].waitForExistence(timeout: 10))
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

    /// TT-162: Demo trains › Platform has the next train leave in 8 min with no platform posted. Its card shows the pill,
    /// which the card's one accessibility element reads as "Platform pending", with no countdown until the number is posted
    /// (TT-248); the later cards keep the dash.
    @MainActor
    func testAwaitingPlatformShowsThePillOnTheNextCardOnly() {
        let app = XCUIApplication.onFixtures()
        app.launchArguments += LaunchArguments.fixtureRoute + ["-settings.demoTrains", "awaitingPlatform"]
        app.launch()

        func card(_ tripId: String) -> XCUIElement {
            app.descendants(matching: .any).matching(identifier: "schedule.card.\(tripId)").firstMatch
        }
        let next = card("LW-0732-20261105")
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        XCTAssertFalse(next.label.contains("in 8 min"), "No countdown beside the dash (TT-248): \(next.label)")
        XCTAssertTrue(next.label.contains("Platform pending"), next.label)
        XCTAssertFalse(next.label.contains("Platform —"), next.label)

        let later = card("LW-0758-20261105")
        XCTAssertTrue(later.waitForExistence(timeout: 5))
        XCTAssertTrue(later.label.contains("Platform —"), later.label)
        XCTAssertFalse(later.label.contains("Platform pending"), later.label)
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
        // Yesterday's tile peeks out from behind the weather tile (TT-226), its middle out of view.
        XCTAssertTrue(yesterday.exists)
        XCTAssertLessThan(yesterday.frame.midX, app.buttons["schedule.weather"].frame.maxX, "The past week is out of view to the left")

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
        // No alert left on the 7:32 AM train: with one, the sheet opens alert-first with no bar (TT-254).
        app.launchArguments += LaunchArguments.fixtureRoute + LaunchArguments.noAlerts
        app.launch()

        // 15 s waits: a slow runner can take several seconds to show what a Mac shows at once (CLAUDE.md).
        let card = app.descendants(matching: .any).matching(identifier: "schedule.card.LW-0732-20261105").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15), "The card is on the timeline")
        card.tap()
        let sheet = app.descendants(matching: .any).matching(identifier: "sheet.tripDetails").firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 15), "The card opens Trip details")
        let last = app.descendants(matching: .any).matching(identifier: "trip.stop.UN").firstMatch
        XCTAssertTrue(last.waitForExistence(timeout: 15), "The trip lists Union")
        let alert = app.buttons["trip.alert"]
        XCTAssertTrue(alert.waitForExistence(timeout: 15), "The alert bar shows")
        XCTAssertTrue(app.buttons["trip.directions"].exists, "Directions to Oakville GO before the train leaves (TT-188)")

        // The whole list is reachable: scroll to the last stop, which then sits above the floating button (TT-163).
        if !last.isHittable { sheet.swipeUp() }
        let reachable = expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: last)
        XCTAssertEqual(XCTWaiter().wait(for: [reachable], timeout: 15), .completed, "Union is reachable at the end of the list")
        XCTAssertLessThanOrEqual(last.frame.maxY, alert.frame.minY)

        app.buttons["trip.close"].tap()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 15), "Close closes the sheet")
        XCTAssertTrue(card.exists, "The timetable is back")
    }

    /// Interest taps (TT-209) change nothing: the line name opens nothing, a tap on a card's time still opens Trip details
    /// (the card's own tap), and a stop row there leaves the sheet as it was.
    @MainActor
    func testInterestTapsChangeNothing() {
        let app = XCUIApplication.onFixtures()
        app.launchArguments += LaunchArguments.fixtureRoute
        app.launch()

        let card = app.descendants(matching: .any).matching(identifier: "schedule.card.LW-0732-20261105").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        let sheet = app.descendants(matching: .any).matching(identifier: "sheet.tripDetails").firstMatch

        app.descendants(matching: .any).matching(identifier: "schedule.line").firstMatch.tap()
        XCTAssertFalse(sheet.waitForExistence(timeout: 2), "The line name opens nothing")
        XCTAssertTrue(card.isHittable)

        // The departure time sits at the card's top left.
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.2)).tap()
        XCTAssertTrue(sheet.waitForExistence(timeout: 15), "The card still opens Trip details")

        let stop = app.descendants(matching: .any).matching(identifier: "trip.stop.UN").firstMatch
        XCTAssertTrue(stop.waitForExistence(timeout: 15))
        if !stop.isHittable { sheet.swipeUp() }
        stop.tap()
        XCTAssertTrue(sheet.exists)
        XCTAssertTrue(app.buttons["trip.close"].isHittable, "Nothing covers the sheet")
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
