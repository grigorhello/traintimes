import XCTest

final class RecentRoutesTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// D48, D54: the station picker lists the other direction under Recent after a swap; tapping it opens that route, and
    /// a relaunch restores the last route and the recent routes.
    @MainActor
    func testRecentRouteOpensFromTheStationPickerAndSurvivesRelaunch() {
        let app = XCUIApplication.onFixtures()
        app.launchArguments += LaunchArguments.fixtureRoute + LaunchArguments.noRecents
        app.launch()

        let from = app.buttons["schedule.from"]
        let to = app.buttons["schedule.to"]
        XCTAssertTrue(from.waitForExistence(timeout: 10))
        expect(from, value: "Oakville")
        expect(to, value: "Union")
        app.buttons["schedule.swap"].tap()
        expect(from, value: "Union")
        expect(to, value: "Oakville")

        // Recent leaves out the route on screen and lists the one before it.
        from.tap()
        let recent = app.buttons["route.recent.OA-UN"]
        XCTAssertTrue(recent.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["route.recent.UN-OA"].exists)
        recent.tap()
        expect(from, value: "Oakville")
        expect(to, value: "Union")

        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(from.waitForExistence(timeout: 10))
        expect(from, value: "Oakville")
        expect(to, value: "Union")
        from.tap()
        XCTAssertTrue(app.buttons["route.recent.UN-OA"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func expect(_ element: XCUIElement, value: String, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "value == %@", value)
        let result = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 5)
        XCTAssertEqual(result, .completed, "\(String(describing: element.value)) is not \(value)", file: file, line: line)
    }
}
