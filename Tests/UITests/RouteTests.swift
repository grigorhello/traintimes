import XCTest

final class RouteTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Acceptance (TT-120, TT-121, TT-161): fresh install; tapping From makes the row the search field with the suggestions
    /// under the card and no sheet, X cancels, typing "oak" and tapping Oakville GO moves on to To, Union Station GO enables
    /// Show trains, then the timeline with no prompt; a relaunch opens the remembered route.
    @MainActor
    func testFirstUseShowsTrainsAndRelaunchOpensTheRoute() {
        let app = XCUIApplication.onFixtures()
        app.launchArguments += LaunchArguments.freshInstall
        app.launch()

        XCTAssertTrue(app.staticTexts["route.title"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.alerts.firstMatch.exists)
        let showTrains = app.buttons["route.showTrains"]
        XCTAssertFalse(showTrains.isEnabled)

        // The row becomes the field, the X takes the swap button's place, and Show trains steps aside.
        app.buttons["route.from"].tap()
        let from = app.textFields["route.from"]
        XCTAssertTrue(from.waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["stations.panel"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["route.swap"].exists)
        XCTAssertTrue(showTrains.waitForNonExistence(timeout: 5))
        app.buttons["route.cancel"].tap()
        XCTAssertTrue(app.buttons["route.from"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["stations.panel"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(showTrains.waitForExistence(timeout: 5))

        // Typing "oak" finds Oakville GO in the panel.
        app.buttons["route.from"].tap()
        XCTAssertTrue(from.waitForExistence(timeout: 5))
        from.tap()
        from.typeText("oak")
        let oakville = app.buttons["station.OA"]
        XCTAssertTrue(oakville.waitForExistence(timeout: 5))
        oakville.tap()
        // Picking From moves straight on to To, with Union Station GO suggested first.
        XCTAssertTrue(app.textFields["route.to"].waitForExistence(timeout: 5))
        let union = app.buttons["station.UN"]
        XCTAssertTrue(union.waitForExistence(timeout: 5))
        union.tap()

        XCTAssertTrue(showTrains.waitForExistence(timeout: 5))
        wait(for: [expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: showTrains)], timeout: 5)
        showTrains.tap()

        let schedule = scheduleStations(app)
        XCTAssertTrue(schedule.from.waitForExistence(timeout: 5))
        XCTAssertEqual(schedule.from.value as? String, "Oakville GO")
        XCTAssertEqual(schedule.to.value as? String, "Union Station GO")
        XCTAssertFalse(app.alerts.firstMatch.exists)

        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(schedule.from.waitForExistence(timeout: 10))
        XCTAssertEqual(schedule.from.value as? String, "Oakville GO")
        XCTAssertEqual(schedule.to.value as? String, "Union Station GO")
    }

    /// Acceptance (TT-161): on Schedule a tap on To opens the picker in place with the swap button turned into the X; X
    /// changes nothing; typing "bur" and tapping Burlington GO applies the route at once.
    @MainActor
    func testScheduleChangesTheDestinationInPlace() {
        let app = XCUIApplication.onFixtures()
        app.launchArguments += LaunchArguments.fixtureRoute + LaunchArguments.noRecents
        app.launch()

        let schedule = scheduleStations(app)
        XCTAssertTrue(schedule.to.waitForExistence(timeout: 10))
        XCTAssertEqual(schedule.to.value as? String, "Union")

        schedule.to.tap()
        let field = app.textFields["schedule.to"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["stations.panel"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["schedule.swap"].exists)

        // The X cancels and nothing changes.
        app.buttons["schedule.cancel"].tap()
        XCTAssertTrue(schedule.to.waitForExistence(timeout: 5))
        XCTAssertEqual(schedule.to.value as? String, "Union")
        XCTAssertTrue(app.buttons["schedule.swap"].waitForExistence(timeout: 5))

        schedule.to.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("bur")
        let burlington = app.buttons["station.BU"]
        XCTAssertTrue(burlington.waitForExistence(timeout: 5))
        burlington.tap()

        XCTAssertTrue(schedule.to.waitForExistence(timeout: 5))
        wait(for: [expectation(for: NSPredicate(format: "value == %@", "Burlington GO"), evaluatedWith: schedule.to)], timeout: 5)
        XCTAssertEqual(schedule.from.value as? String, "Oakville")
        XCTAssertTrue(app.otherElements["stations.panel"].waitForNonExistence(timeout: 5))
    }

    @MainActor
    private func scheduleStations(_ app: XCUIApplication) -> (from: XCUIElement, to: XCUIElement) {
        (app.buttons["schedule.from"], app.buttons["schedule.to"])
    }
}
