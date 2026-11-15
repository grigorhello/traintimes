import XCTest

/// The first launch (TT-206): a fresh install opens on the welcome with no tab bar; "Choose your line", a line and a station
/// open Schedule on that route in three taps, and a tile on the picture does it in two. The fixture clock is 7:21 AM, so the
/// route runs from the station to Union.
final class WelcomeTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testThreeTapsOpenScheduleOnTheRoute() {
        let app = XCUIApplication.onFixtures()
        app.launchArguments += LaunchArguments.freshInstall
        app.launch()

        let choose = app.buttons["welcome.choose"]
        require(choose, "welcome.choose", in: app)
        XCTAssertFalse(app.tabBars.firstMatch.exists, "No tab bar before the first trains")
        choose.tap()

        let lakeshoreWest = app.buttons["welcome.line.LW"]
        require(lakeshoreWest, "welcome.line.LW", in: app)
        XCTAssertTrue(app.buttons["welcome.search"].exists)
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        lakeshoreWest.tap()

        let oakville = app.buttons["welcome.station.OA"]
        require(oakville, "welcome.station.OA", in: app)
        XCTAssertFalse(app.buttons["welcome.station.UN"].exists, "Union is not listed")
        oakville.tap()

        let from = app.buttons["schedule.from"]
        require(from, "schedule.from", in: app)
        XCTAssertEqual(from.value as? String, "Oakville GO")
        XCTAssertEqual(app.buttons["schedule.to"].value as? String, "Union Station GO")
        XCTAssertTrue(app.tabBars.buttons["Schedule"].waitForExistence(timeout: 15), "The tab bar comes with the first trains")
        XCTAssertFalse(app.alerts.firstMatch.exists, "No permission is asked")
    }

    /// A tile on the welcome's picture skips the list; the X goes back to the lines.
    @MainActor
    func testATileOnThePictureSkipsTheList() {
        let app = XCUIApplication.onFixtures()
        app.launchArguments += LaunchArguments.freshInstall
        app.launch()

        let tile = app.buttons["welcome.map.LW"]
        require(tile, "welcome.map.LW", in: app)
        tile.tap()
        require(app.buttons["welcome.station.OA"], "welcome.station.OA", in: app)

        app.buttons["welcome.swap"].tap()
        require(app.buttons["welcome.line.LW"], "welcome.line.LW", in: app)
        app.buttons["welcome.line.LW"].tap()
        let oakville = app.buttons["welcome.station.OA"]
        require(oakville, "welcome.station.OA", in: app)
        oakville.tap()
        let from = app.buttons["schedule.from"]
        require(from, "schedule.from", in: app)
        XCTAssertEqual(from.value as? String, "Oakville GO")
    }

    /// Waits for `element` (15 s for slow runners); on a miss fails with what is on screen.
    @MainActor
    private func require(
        _ element: XCUIElement, _ what: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line
    ) {
        guard !element.waitForExistence(timeout: 15) else { return }
        XCTFail("\(what) is missing. On screen:\n\(app.debugDescription.prefix(7000))", file: file, line: line)
    }
}
