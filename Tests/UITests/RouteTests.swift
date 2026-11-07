import XCTest

final class RouteTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Acceptance (TT-120, TT-121): fresh install, search and pick Oakville GO, pick Union Station GO, Show trains,
    /// timeline, with no prompt; a relaunch opens the remembered route.
    @MainActor
    func testFirstUseShowsTrainsAndRelaunchOpensTheRoute() {
        let app = XCUIApplication()
        app.launchArguments += LaunchArguments.freshInstall
        app.launch()

        XCTAssertTrue(app.staticTexts["route.title"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.alerts.firstMatch.exists)
        let showTrains = app.buttons["route.showTrains"]
        XCTAssertFalse(showTrains.isEnabled)

        // Station search (TT-121): typing "oak" finds Oakville GO.
        app.buttons["route.from"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("oak")
        let oakville = app.buttons["station.OA"]
        XCTAssertTrue(oakville.waitForExistence(timeout: 5))
        oakville.tap()
        // Picking From moves straight on to To, with Union Station GO suggested first.
        let title = app.staticTexts["stations.title"]
        wait(for: [expectation(for: NSPredicate(format: "label == 'To'"), evaluatedWith: title)], timeout: 5)
        let union = app.buttons["station.UN"]
        XCTAssertTrue(union.waitForExistence(timeout: 5))
        union.tap()

        wait(for: [expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: showTrains)], timeout: 5)
        showTrains.tap()

        let route = app.buttons["schedule.route"]
        XCTAssertTrue(route.waitForExistence(timeout: 5))
        XCTAssertTrue(route.label.hasPrefix("Oakville GO to Union Station GO"), route.label)
        XCTAssertFalse(app.alerts.firstMatch.exists)

        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(route.waitForExistence(timeout: 10))
        XCTAssertTrue(route.label.hasPrefix("Oakville GO to Union Station GO"), route.label)
    }
}
