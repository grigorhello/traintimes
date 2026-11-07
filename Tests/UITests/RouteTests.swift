import XCTest

final class RouteTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Acceptance (TT-120): fresh install, pick Oakville, pick Union, Show trains, timeline, with no prompt;
    /// a relaunch opens the remembered route.
    @MainActor
    func testFirstUseShowsTrainsAndRelaunchOpensTheRoute() {
        let app = XCUIApplication()
        app.launchArguments += LaunchArguments.freshInstall
        app.launch()

        XCTAssertTrue(app.staticTexts["route.title"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.alerts.firstMatch.exists)
        let showTrains = app.buttons["route.showTrains"]
        XCTAssertFalse(showTrains.isEnabled)

        app.buttons["route.from"].tap()
        let oakville = app.buttons["station.OA"]
        XCTAssertTrue(oakville.waitForExistence(timeout: 5))
        oakville.tap()
        // Picking From moves straight on to To.
        XCTAssertTrue(app.navigationBars["To"].waitForExistence(timeout: 5))
        app.buttons["station.UN"].tap()

        wait(for: [expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: showTrains)], timeout: 5)
        showTrains.tap()

        let route = app.buttons["schedule.route"]
        XCTAssertTrue(route.waitForExistence(timeout: 5))
        XCTAssertTrue(route.label.hasPrefix("Oakville to Union"), route.label)
        XCTAssertFalse(app.alerts.firstMatch.exists)

        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(route.waitForExistence(timeout: 10))
        XCTAssertTrue(route.label.hasPrefix("Oakville to Union"), route.label)
    }
}
