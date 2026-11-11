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
        XCTAssertTrue(from.waitForExistence(timeout: Self.waitTime))
        expect(from, value: "Oakville")
        expect(to, value: "Union")
        app.buttons["schedule.swap"].tap()
        expect(from, value: "Union")
        expect(to, value: "Oakville")

        // Recent leaves out the route on screen and lists the one before it.
        from.tap()
        let recent = app.buttons["route.recent.OA-UN"]
        XCTAssertTrue(recent.waitForExistence(timeout: Self.waitTime))
        XCTAssertFalse(app.buttons["route.recent.UN-OA"].exists)
        recent.tap()
        expect(from, value: "Oakville")
        expect(to, value: "Union")

        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(from.waitForExistence(timeout: Self.waitTime))
        expect(from, value: "Oakville")
        expect(to, value: "Union")
        from.tap()
        XCTAssertTrue(app.buttons["route.recent.UN-OA"].waitForExistence(timeout: Self.waitTime))
    }

    /// A query's first check takes about a second on a Mac and can take over 5 s on a slow CI runner, so a 5 s wait timed
    /// out with the right value already on screen (main after TT-164, on runners twice as slow as usual).
    private static let waitTime: TimeInterval = 15

    @MainActor
    private func expect(_ element: XCUIElement, value: String, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "value == %@", value)
        let result = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: Self.waitTime)
        // The line goes in the message too: the CI log drops the failure's location.
        XCTAssertEqual(
            result, .completed, "line \(line): \(String(describing: element.value)) is not \(value)", file: file, line: line
        )
    }
}
