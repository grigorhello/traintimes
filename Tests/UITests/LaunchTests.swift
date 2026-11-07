import XCTest

final class LaunchTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Launch lands on Schedule with no prompt; the gear pushes Settings and back returns (TT-104).
    @MainActor
    func testLaunchLandsOnScheduleAndGearPushesSettings() {
        let app = XCUIApplication()
        app.launch()

        let title = app.staticTexts["schedule.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.label, "Train Times")
        XCTAssertTrue(app.tabBars.buttons["Schedule"].isSelected)
        XCTAssertTrue(app.tabBars.buttons["Alerts"].exists)
        XCTAssertFalse(app.alerts.firstMatch.exists)

        app.buttons["schedule.settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))

        app.navigationBars["Settings"].buttons.firstMatch.tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
    }
}
