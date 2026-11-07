import XCTest

/// Alert setup (TT-142): the iOS permission dialog comes only after the first "Enable alerts", and a denied permission
/// shows Notifications off with Open Settings, never On. The app runs on the fixture schedule and alert server.
final class AlertSetupTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Trip details › Alert me › Enable alerts › Allow › On, and the sheet turns into Manage alert.
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

        // "Setting up" while the permission and the save are in flight, then On.
        let state = app.descendants(matching: .any).matching(identifier: "alert.state").firstMatch
        XCTAssertTrue(state.waitForExistence(timeout: 10))
        let on = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "On"), object: state)
        XCTAssertEqual(XCTWaiter().wait(for: [on], timeout: 10), .completed)
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

    /// The 7:32 AM card, then its Trip details "Alert me".
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
