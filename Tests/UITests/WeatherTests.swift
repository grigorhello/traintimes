import XCTest

/// TT-226: the weather tile follows the selected day, and a tap opens the sheet with Apple's attribution.
final class WeatherTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testTileFollowsTheDayAndOpensTheSheet() {
        let app = XCUIApplication.onFixtures()
        app.launchArguments += LaunchArguments.fixtureRoute
        app.launch()

        let tile = app.buttons["schedule.weather"]
        XCTAssertTrue(tile.waitForExistence(timeout: 15))
        XCTAssertEqual(tile.value as? String, "4°")

        app.buttons["schedule.day.2"].tap()
        let saturday = expectation(for: NSPredicate(format: "value == %@", "1°"), evaluatedWith: tile)
        wait(for: [saturday], timeout: 15)

        tile.tap()
        XCTAssertTrue(app.descendants(matching: .any)["weather.sheet"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.descendants(matching: .any)["weather.attribution"].exists)
    }
}
