import XCTest

final class LaunchTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Launch lands on Schedule with no prompt, the line name and the route card right under the status bar with no app
    /// name above them, and Settings is the third tab (TT-104, D48, D49).
    @MainActor
    func testLaunchLandsOnScheduleAndSettingsIsATab() {
        let app = XCUIApplication.onFixtures()
        app.launchArguments += LaunchArguments.fixtureRoute
        app.launch()

        let route = app.buttons["schedule.route"]
        XCTAssertTrue(route.waitForExistence(timeout: 10))
        let line = app.descendants(matching: .any)["schedule.line"]
        XCTAssertEqual(line.label, "Lakeshore West", "The line comes first (D49)")
        XCTAssertLessThan(line.frame.minY, 100, "The line row sits right under the status bar, as on the canvas")
        XCTAssertLessThan(route.frame.minY, 170, "The route card follows the line row")
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
