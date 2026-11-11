import XCTest

/// Alert setup (TT-142): the iOS permission dialog comes only after the first "Enable alerts", and a denied permission
/// shows Notifications off with Open Settings, never On. The app runs on the fixture schedule and alert server.
final class AlertSetupTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Trip details › Alert me › Enable alerts › Allow › On: the check, a 0.3 s hold and the sheet closes by itself with the
    /// card's bell on (TT-166); opened again, the sheet manages the alert: On, Manage alert and Delete alert.
    @MainActor
    func testEnableAsksPermissionThenOn() {
        let app = XCUIApplication.onFixtures()
        app.launchArguments += LaunchArguments.fixtureRoute + LaunchArguments.noAlerts
        app.launch()
        openAlertSetup(app)

        XCTAssertTrue(app.staticTexts["Alert for this train"].exists)
        app.buttons["alert.enable"].tap()

        // The system dialog, answered here unless an earlier run on this simulator already allowed notifications.
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons["Allow"]
        if allow.waitForExistence(timeout: 5) {
            allow.tap()
        }

        // "Setting up" while the permission and the save are in flight, then On: the sheet closes and the bell is on.
        let sheet = app.descendants(matching: .any).matching(identifier: "sheet.alertSetup").firstMatch
        XCTAssertTrue(wait(for: sheet, predicate: "exists == false"))
        let bell = app.buttons["schedule.bell.LW-0732-20261105"]
        XCTAssertTrue(wait(for: bell, predicate: "label == 'Alert on for 7:32 AM train'"))

        openAlertSetup(app)
        let state = app.descendants(matching: .any).matching(identifier: "alert.state").firstMatch
        XCTAssertTrue(state.waitForExistence(timeout: 10))
        XCTAssertTrue(wait(for: state, predicate: "label == 'On'"))
        XCTAssertTrue(app.staticTexts["Manage alert"].exists)
        XCTAssertTrue(app.buttons["alert.delete"].exists)
    }

    /// With notifications turned off the rule is saved but the sheet shows the red panel and Open Settings, never On.
    @MainActor
    func testDeniedShowsNotificationsOff() {
        let app = XCUIApplication.onFixtures()
        app.launchEnvironment["TT_NOTIFICATIONS"] = "off"
        app.launchArguments += LaunchArguments.fixtureRoute + LaunchArguments.noAlerts
        app.launch()
        openAlertSetup(app)

        app.buttons["alert.enable"].tap()

        XCTAssertTrue(app.buttons["alert.openSettings"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "alert.denied").firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "alert.state").firstMatch.exists)
    }

    private func wait(for element: XCUIElement, predicate: String) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: 10) == .completed
    }

    /// The 7:32 AM card, then its Trip details "Alert me" (or "Manage alert").
    @MainActor
    private func openAlertSetup(_ app: XCUIApplication) {
        let card = app.descendants(matching: .any).matching(identifier: "schedule.card.LW-0732-20261105").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()
        let alertMe = app.buttons["trip.alert"]
        XCTAssertTrue(alertMe.waitForExistence(timeout: 5))
        alertMe.tap()
        let sheet = app.descendants(matching: .any).matching(identifier: "sheet.alertSetup").firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
    }
}
