import XCTest

/// The Alerts tab as one list (TT-193): a row opens in place, a day tile changes the same alert, Remove alert removes it
/// and Undo brings it back; the empty tab's next trains set the first alert with their bells; with notifications off the
/// card tops the list and the switches are disabled. The app runs on the fixture schedule and alert server.
final class AlertsTabTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// The 7:32 AM train's bell on Schedule, then on Alerts: open the row, light Thursday, Remove alert, Undo.
    @MainActor
    func testOpenARowChangeADayRemoveAndUndo() {
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
        // Schedule stays in the tab view with its own capsule and day panel, so look inside the Alerts tab only.
        let alerts = app.descendants(matching: .any).matching(identifier: "alerts.root").firstMatch
        let row = alerts.descendants(matching: .any).matching(identifier: "alerts.rule.LW-0732-20261105").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        let open = row.buttons["alerts.rule.open"]
        XCTAssertTrue(wait(for: open, labelContains: "Oakville to Union · Today only"))

        open.tap()
        XCTAssertTrue(row.staticTexts["Repeat on"].waitForExistence(timeout: 15))
        row.buttons["alert.day.4"].tap()
        XCTAssertTrue(wait(for: open, labelContains: "Oakville to Union · Thu"))

        row.buttons["alerts.remove"].tap()
        XCTAssertTrue(alerts.staticTexts["Alert removed"].waitForExistence(timeout: 15))
        XCTAssertTrue(row.waitForNonExistence(timeout: 15))

        alerts.buttons["alert.capsule.action"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        XCTAssertTrue(wait(for: open, labelContains: "Oakville to Union · Thu"), "back with the same days")
    }

    /// With no alert, the next trains stand in; a bell there sets the first alert, which takes their place.
    @MainActor
    func testTheFirstAlertFromTheNextTrains() {
        let app = XCUIApplication.onFixtures()
        app.launchEnvironment["TT_NOTIFICATIONS"] = "allowed"
        app.launchArguments += LaunchArguments.fixtureRoute + LaunchArguments.noAlerts
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Alerts"].waitForExistence(timeout: 20))
        // Schedule has loaded today's trains before the tab opens.
        XCTAssertTrue(app.buttons["schedule.bell.LW-0732-20261105"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Alerts"].tap()
        XCTAssertTrue(app.staticTexts["Next trains"].waitForExistence(timeout: 15))
        let bell = app.buttons["alerts.next.bell.LW-0732-20261105"]
        XCTAssertTrue(bell.waitForExistence(timeout: 15))
        bell.tap()

        let row = app.descendants(matching: .any).matching(identifier: "alerts.rule.LW-0732-20261105").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Alerts start 1 hour before each train leaves."].exists)
    }

    /// TT-169 and TT-193: with notifications off and an alert on, the card tops the tab and the switch is disabled.
    @MainActor
    func testNotificationsOffShowsTheCardAndDisablesTheSwitches() {
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

        XCTAssertTrue(app.tabBars.buttons["Alerts"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Alerts"].tap()
        let warning = app.descendants(matching: .any).matching(identifier: "alerts.notificationsOff").firstMatch
        XCTAssertTrue(warning.waitForExistence(timeout: 15))
        XCTAssertTrue(warning.staticTexts["Notifications are off"].exists)
        XCTAssertTrue(warning.staticTexts["1 alert can’t reach you."].exists)
        XCTAssertTrue(app.buttons["alerts.turnOnInSettings"].exists)
        let row = app.descendants(matching: .any).matching(identifier: "alerts.rule.LW-0732-20261105").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        XCTAssertFalse(row.switches["alerts.rule.switch"].isEnabled, "disabled while notifications are off")
        XCTAssertFalse(app.staticTexts["Alerts start 1 hour before each train leaves."].exists)
    }

    private func wait(for element: XCUIElement, labelContains text: String) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", text), object: element)
        return XCTWaiter.wait(for: [expectation], timeout: 15) == .completed
    }

    private func wait(for element: XCUIElement, label: String) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: element)
        return XCTWaiter.wait(for: [expectation], timeout: 15) == .completed
    }
}
