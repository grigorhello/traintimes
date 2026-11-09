import XCTest

final class NoTrainsTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// A day with no direct trains offers the next day that has some (TT-115). The fixtures run no trains on Sundays,
    /// so on the fixture clock (Thu Nov 5) cell 3, Sun 8, shows the empty card and "Show Monday" selects cell 4.
    @MainActor
    func testNoTrainsDayShowsTheNextDayWithTrains() {
        let app = XCUIApplication.onFixtures()
        app.launchArguments += LaunchArguments.fixtureRoute
        app.launch()

        XCTAssertTrue(app.buttons["schedule.route"].waitForExistence(timeout: 10))
        app.buttons["schedule.day.3"].tap()
        let title = app.staticTexts.matching(NSPredicate(format: "label == %@", "No direct trains on Sunday")).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5))

        let showMonday = app.buttons["emptyState.action"]
        XCTAssertEqual(showMonday.label, "Show Monday")
        showMonday.tap()
        let card = app.descendants(matching: .any).matching(identifier: "schedule.card.LW-0732-20261105").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["schedule.day.4"].isSelected)
    }
}
