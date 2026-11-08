import XCTest

final class SettingsTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Settings shows the permission in words and changes Appearance and Time format (TT-105).
    @MainActor
    func testChangeAppearanceAndTimeFormat() {
        let app = XCUIApplication.onFixtures()
        // Not asked yet, whatever an earlier test answered in the iOS dialog (TT-142).
        app.launchEnvironment["TT_NOTIFICATIONS"] = "notAsked"
        // Start from the defaults whatever an earlier run stored.
        app.launchArguments += ["-settings.appearance", "system", "-settings.timeFormat", "device"]
        app.launch()

        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["settings.title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["System"].isSelected)
        XCTAssertTrue(app.buttons["Device"].isSelected)
        XCTAssertTrue(app.staticTexts["Notification permission"].exists)
        // The app never asks before an alert is set (TT-142), so a fresh install reads Not asked yet.
        let permission = app.descendants(matching: .any)["settings.permission"]
        XCTAssertTrue(permission.waitForExistence(timeout: 5))
        XCTAssertEqual(permission.label, "Not asked yet")

        app.buttons["Dark"].tap()
        XCTAssertTrue(app.buttons["Dark"].isSelected)
        XCTAssertFalse(app.buttons["System"].isSelected)
        app.buttons["24-hour"].tap()
        XCTAssertTrue(app.buttons["24-hour"].isSelected)

        // Leave the simulator on the defaults for the next run.
        app.buttons["System"].tap()
        app.buttons["Device"].tap()
        XCTAssertTrue(app.buttons["System"].isSelected)
    }
}
