import XCTest

final class FavouritesTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Acceptance (TT-122): the star keeps this direction only, the route sheet lists the favourite and opens it, and a
    /// relaunch restores the last route, its direction and the favourites.
    @MainActor
    func testStarListsTheFavouriteAndRelaunchRestoresTheDirection() {
        let app = XCUIApplication.onFixtures()
        app.launchArguments += LaunchArguments.fixtureRoute + LaunchArguments.noFavourites
        app.launch()

        let route = app.buttons["schedule.route"]
        let star = app.buttons["schedule.favourite"]
        let swap = app.buttons["schedule.swap"]
        XCTAssertTrue(route.waitForExistence(timeout: 10))
        expect(star, label: "Add to favourites")
        star.tap()
        expect(star, label: "Remove from favourites")

        // Each direction is its own favourite.
        swap.tap()
        expect(route, labelPrefix: "Union to Oakville")
        expect(star, label: "Add to favourites")

        // The route sheet lists the favourite; tapping it opens that route.
        route.tap()
        let favourite = app.buttons["route.favourite.OA-UN"]
        XCTAssertTrue(favourite.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["route.favouritesCount"].label, "1 of 3")
        favourite.tap()
        expect(route, labelPrefix: "Oakville to Union")
        expect(star, label: "Remove from favourites")

        // The last direction and the favourites are restored on relaunch.
        swap.tap()
        expect(route, labelPrefix: "Union to Oakville")
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(route.waitForExistence(timeout: 10))
        expect(route, labelPrefix: "Union to Oakville")
        expect(star, label: "Add to favourites")
        swap.tap()
        expect(star, label: "Remove from favourites")
    }

    @MainActor
    private func expect(_ element: XCUIElement, label: String, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "label == %@", label)
        let result = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 5)
        XCTAssertEqual(result, .completed, "\(element.label) is not \(label)", file: file, line: line)
    }

    @MainActor
    private func expect(_ element: XCUIElement, labelPrefix: String, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "label BEGINSWITH %@", labelPrefix)
        let result = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 5)
        XCTAssertEqual(result, .completed, "\(element.label) does not start with \(labelPrefix)", file: file, line: line)
    }
}
