import XCTest

final class RecentRoutesTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// D48: the route card opens the route sheet, which lists the other direction under Recent after a swap; tapping it
    /// opens that route, and a relaunch restores the last route and the recent routes.
    @MainActor
    func testRecentRouteOpensFromTheRouteSheetAndSurvivesRelaunch() {
        let app = XCUIApplication.onFixtures()
        app.launchArguments += LaunchArguments.fixtureRoute + LaunchArguments.noRecents
        app.launch()

        let route = app.buttons["schedule.route"]
        XCTAssertTrue(route.waitForExistence(timeout: 10))
        expect(route, label: "Oakville to Union")
        app.buttons["schedule.swap"].tap()
        expect(route, label: "Union to Oakville")

        // The sheet leaves out the route on screen and lists the one before it.
        route.tap()
        let recent = app.buttons["route.recent.OA-UN"]
        XCTAssertTrue(recent.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["route.recent.UN-OA"].exists)
        recent.tap()
        expect(route, label: "Oakville to Union")

        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(route.waitForExistence(timeout: 10))
        expect(route, label: "Oakville to Union")
        route.tap()
        XCTAssertTrue(app.buttons["route.recent.UN-OA"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func expect(_ element: XCUIElement, label: String, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "label == %@", label)
        let result = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 5)
        XCTAssertEqual(result, .completed, "\(element.label) is not \(label)", file: file, line: line)
    }
}
