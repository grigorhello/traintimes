import XCTest

/// TT-172, TT-175: Demo trains › Ride first asks on Schedule "On the 5:13 PM train?" (about 25 s after launch), and its Yes
/// starts the ride from Union to Clarkson and opens Trip details in ride mode. Closing the sheet keeps the ride and the
/// strip opens it again; End ride ends it and the strip goes.
final class OnBoardTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testDemoQuestionYesStartsTheRideAndEndRideEndsIt() {
        let app = XCUIApplication.onFixtures()
        app.launchArguments += LaunchArguments.fixtureRoute + ["-settings.demoTrains", "ride"]
        app.launch()

        let question = app.descendants(matching: .any).matching(identifier: "schedule.question").firstMatch
        XCTAssertTrue(question.waitForExistence(timeout: 60))
        let strip = app.descendants(matching: .any).matching(identifier: "schedule.ride").firstMatch
        XCTAssertFalse(strip.exists, "No ride starts before the tap")

        app.buttons["schedule.question.yes"].tap()
        let card = app.descendants(matching: .any).matching(identifier: "trip.ride").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10), "Yes opens Trip details in ride mode")

        // Closing the sheet keeps the ride: the strip has taken the question's place and opens it again.
        app.buttons["trip.close"].tap()
        XCTAssertTrue(card.waitForNonExistence(timeout: 5))
        XCTAssertTrue(strip.waitForExistence(timeout: 5))
        XCTAssertTrue(strip.label.contains("On board"), strip.label)
        XCTAssertFalse(question.exists)
        strip.tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5))

        app.buttons["trip.endRide"].tap()
        XCTAssertTrue(card.waitForNonExistence(timeout: 5))
        XCTAssertTrue(strip.waitForNonExistence(timeout: 5), "End ride ends the ride, and the strip goes")
    }
}
