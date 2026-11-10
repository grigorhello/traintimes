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

        require(app.staticTexts["route.title"], "staticTexts[route.title]", in: app)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        let showTrains = app.buttons["route.showTrains"]
        XCTAssertFalse(showTrains.isEnabled)

        // The row becomes the field, the X takes the swap button's place, and Show trains steps aside.
        app.buttons["route.from"].tap()
        let from = app.textFields["route.from"]
        require(from, "from", in: app)
        require(panel(app), "stations.panel", in: app)
        XCTAssertFalse(app.buttons["route.swap"].exists)
        requireGone(showTrains, "route.showTrains", in: app)
        app.buttons["route.cancel"].tap()
        require(app.buttons["route.from"], "buttons[route.from]", in: app)
        requireGone(panel(app), "stations.panel", in: app)
        require(showTrains, "showTrains", in: app)

        // Typing "oak" finds Oakville GO in the panel.
        app.buttons["route.from"].tap()
        require(from, "from", in: app)
        from.tap()
        from.typeText("oak")
        let oakville = app.buttons["station.OA"]
        require(oakville, "oakville", in: app)
        oakville.tap()
        // Picking From moves straight on to To, with Union Station GO suggested first.
        require(app.textFields["route.to"], "textFields[route.to]", in: app)
        let union = app.buttons["station.UN"]
        require(union, "union", in: app)
        union.tap()

        require(showTrains, "showTrains", in: app)
        wait(for: [expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: showTrains)], timeout: 5)
        showTrains.tap()

        let schedule = scheduleStations(app)
        require(schedule.from, "schedule.from", in: app)
        XCTAssertEqual(schedule.from.value as? String, "Oakville GO")
        XCTAssertEqual(schedule.to.value as? String, "Union Station GO")
        XCTAssertFalse(app.alerts.firstMatch.exists)

        app.terminate()
        app.launchArguments = []
        app.launch()
        require(schedule.from, "schedule.from", in: app)
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
        require(schedule.to, "schedule.to", in: app)
        XCTAssertEqual(schedule.to.value as? String, "Union")

        schedule.to.tap()
        let field = app.textFields["schedule.to"]
        require(field, "field", in: app)
        require(panel(app), "stations.panel", in: app)
        XCTAssertFalse(app.buttons["schedule.swap"].exists)

        // The X cancels and nothing changes.
        app.buttons["schedule.cancel"].tap()
        require(schedule.to, "schedule.to", in: app)
        XCTAssertEqual(schedule.to.value as? String, "Union")
        require(app.buttons["schedule.swap"], "buttons[schedule.swap]", in: app)

        schedule.to.tap()
        require(field, "field", in: app)
        field.tap()
        field.typeText("bur")
        let burlington = app.buttons["station.BU"]
        require(burlington, "burlington", in: app)
        burlington.tap()

        require(schedule.to, "schedule.to", in: app)
        wait(for: [expectation(for: NSPredicate(format: "value == %@", "Burlington GO"), evaluatedWith: schedule.to)], timeout: 5)
        XCTAssertEqual(schedule.from.value as? String, "Oakville")
        requireGone(panel(app), "stations.panel", in: app)
    }

    /// Waits for `element`; on a miss fails with what is on screen, so a red CI log says what the picker looked like.
    @MainActor
    private func require(
        _ element: XCUIElement, _ what: String, in app: XCUIApplication, timeout: TimeInterval = 8,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        guard !element.waitForExistence(timeout: timeout) else { return }
        XCTFail("\(what) is missing. On screen:\n\(app.debugDescription.prefix(7000))", file: file, line: line)
    }

    @MainActor
    private func requireGone(
        _ element: XCUIElement, _ what: String, in app: XCUIApplication, timeout: TimeInterval = 8,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        guard !element.waitForNonExistence(timeout: timeout) else { return }
        XCTFail("\(what) is still there. On screen:\n\(app.debugDescription.prefix(7000))", file: file, line: line)
    }

    /// The suggestions panel, found whatever element type it is exposed as.
    @MainActor
    private func panel(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "stations.panel").firstMatch
    }

    @MainActor
    private func scheduleStations(_ app: XCUIApplication) -> (from: XCUIElement, to: XCUIElement) {
        (app.buttons["schedule.from"], app.buttons["schedule.to"])
    }
}
