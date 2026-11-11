import XCTest

/// The Alerts tab (TT-143): "Add alert" sends the rider to the bells, a rule armed there shows with its state, its switch
/// pauses it, a swipe deletes it and Undo brings it back, and a line notice opens the notice sheet. The app runs on the
/// fixture schedule and alert server.
final class AlertsTabTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// The empty tab's "Add alert": Schedule, with "Tap the bell on a train".
    @MainActor
    func testAddAlertShowsTheBellHintOnSchedule() {
        let app = XCUIApplication.onFixtures()
        app.launchEnvironment["TT_TOAST_SECONDS"] = "60"
        app.launchArguments += LaunchArguments.fixtureRoute + LaunchArguments.noAlerts
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Alerts"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Alerts"].tap()
        XCTAssertTrue(app.staticTexts["No alerts yet"].waitForExistence(timeout: 5))
        app.buttons["emptyState.action"].tap()

        XCTAssertTrue(app.staticTexts["Tap the bell on a train"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.tabBars.buttons["Schedule"].isSelected)
    }

    /// A bell armed on Schedule lists as On; the switch pauses it; swipe and Delete, then Undo, restore it as it was.
    @MainActor
    func testPauseDeleteAndUndo() {
        let app = XCUIApplication.onFixtures()
        app.launchEnvironment["TT_NOTIFICATIONS"] = "allowed"
        app.launchEnvironment["TT_TOAST_SECONDS"] = "60"
        app.launchArguments += LaunchArguments.fixtureRoute + LaunchArguments.noAlerts
        app.launch()

        let bell = app.buttons["schedule.bell.LW-0732-20261105"]
        XCTAssertTrue(bell.waitForExistence(timeout: 20))
        bell.tap()
        XCTAssertTrue(wait(for: bell, label: "Alert on for 7:32 AM train"))

        app.tabBars.buttons["Alerts"].tap()
        let row = app.descendants(matching: .any).matching(identifier: "alerts.rule.trip.LW-0732-20261105").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(row.staticTexts["Today only"].exists)
        let state = row.descendants(matching: .any).matching(identifier: "alerts.rule.state").firstMatch
        XCTAssertTrue(wait(for: state, label: "On"))

        row.switches["alerts.rule.switch"].tap()
        XCTAssertTrue(wait(for: state, label: "Paused"))

        // A full swipe deletes at once; a shorter one shows Delete.
        row.swipeLeft()
        let delete = app.buttons["Delete"]
        if delete.waitForExistence(timeout: 2) { delete.tap() }
        let alerts = app.descendants(matching: .any).matching(identifier: "alerts.root").firstMatch
        XCTAssertTrue(alerts.staticTexts["Alert deleted"].waitForExistence(timeout: 5))
        XCTAssertTrue(row.waitForNonExistence(timeout: 5))

        alerts.buttons["toast.action"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(wait(for: state, label: "Paused"))
    }

    /// TT-169: with notifications off and an alert on, one card tops the tab with its button, and the row reads Not delivering.
    @MainActor
    func testNotificationsOffShowsTheCardAndNotDelivering() {
        // The 7:32 AM train's alert is turned on from its bell with notifications allowed (a tap with them off saves
        // nothing, TT-190), then the app comes back with them off: the alert is kept, not delivered.
        let setup = XCUIApplication.onFixtures()
        setup.launchEnvironment["TT_NOTIFICATIONS"] = "allowed"
        setup.launchArguments += LaunchArguments.fixtureRoute + LaunchArguments.noAlerts
        setup.launch()
        let bell = setup.buttons["schedule.bell.LW-0732-20261105"]
        XCTAssertTrue(bell.waitForExistence(timeout: 20))
        bell.tap()
        XCTAssertTrue(wait(for: bell, label: "Alert on for 7:32 AM train"))
        setup.terminate()

        let app = XCUIApplication.onFixtures()
        app.launchEnvironment["TT_NOTIFICATIONS"] = "off"
        app.launchArguments += LaunchArguments.fixtureRoute
        app.launch()

        app.tabBars.buttons["Alerts"].tap()
        let warning = app.descendants(matching: .any).matching(identifier: "alerts.notificationsOff").firstMatch
        XCTAssertTrue(warning.waitForExistence(timeout: 10))
        XCTAssertTrue(warning.staticTexts["Notifications are off"].exists)
        XCTAssertTrue(warning.staticTexts["Your alert is saved, but it can't reach you."].exists)
        XCTAssertTrue(app.buttons["alerts.turnOnInSettings"].exists)
        let row = app.descendants(matching: .any).matching(identifier: "alerts.rule.trip.LW-0732-20261105").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        let state = row.descendants(matching: .any).matching(identifier: "alerts.rule.state").firstMatch
        XCTAssertTrue(wait(for: state, label: "Not delivering"))
        XCTAssertTrue(row.switches["alerts.rule.switch"].exists, "the switch keeps working")
    }

    /// Today's line notice is listed apart from trip updates and opens the notice sheet.
    @MainActor
    func testLineNoticeOpensTheNoticeSheet() {
        let app = XCUIApplication.onDelayedFixture()
        app.launchArguments += LaunchArguments.fixtureRoute + LaunchArguments.noAlerts + LaunchArguments.noDismissedNotices
        app.launch()

        // Schedule loads the line's notices first.
        XCTAssertTrue(app.buttons["schedule.lineNotice"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Alerts"].tap()
        XCTAssertTrue(app.staticTexts["Line notices"].waitForExistence(timeout: 5))
        let notice = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "alerts.notice.")).firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 5))
        notice.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "sheet.lineNotices").firstMatch.waitForExistence(timeout: 5))
    }

    private func wait(for element: XCUIElement, label: String) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: element)
        return XCTWaiter.wait(for: [expectation], timeout: 10) == .completed
    }
}
