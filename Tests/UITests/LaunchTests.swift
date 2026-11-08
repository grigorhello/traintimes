import XCTest

final class LaunchTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Launch lands on Schedule with no prompt, the route card right under the status bar with no app name above it, and
    /// Settings is the third tab (TT-104, D48).
    @MainActor
    func testLaunchLandsOnScheduleAndSettingsIsATab() {
        let app = XCUIApplication.onFixtures()
        app.launchArguments += LaunchArguments.fixtureRoute
        app.launch()

        let route = app.buttons["schedule.route"]
        XCTAssertTrue(route.waitForExistence(timeout: 10))
        XCTAssertLessThan(route.frame.minY, 100, "The route card sits right under the status bar, as on the canvas")
        XCTAssertTrue(app.tabBars.buttons["Schedule"].isSelected)
        XCTAssertTrue(app.tabBars.buttons["Alerts"].exists)
        XCTAssertFalse(app.alerts.firstMatch.exists)

        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["settings.title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Settings"].isSelected)

        app.tabBars.buttons["Schedule"].tap()
        XCTAssertTrue(route.waitForExistence(timeout: 5))
    }
}
