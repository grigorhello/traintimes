import XCTest

/// TT-172: Demo trains › Ride plays a ride from Union to Clarkson. The ride strip on Schedule opens Trip details in ride
/// mode; closing the sheet keeps the ride, and End ride ends it and the strip goes.
final class OnBoardTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testDemoRideOpensRideModeAndEndRideEndsIt() {
        let app = XCUIApplication.onFixtures()
        app.launchArguments += LaunchArguments.fixtureRoute + ["-settings.demoTrains", "ride"]
        app.launch()

        let strip = app.descendants(matching: .any).matching(identifier: "schedule.ride").firstMatch
        XCTAssertTrue(strip.waitForExistence(timeout: 10))
        XCTAssertTrue(strip.label.contains("On board"), strip.label)

        strip.tap()
        let card = app.descendants(matching: .any).matching(identifier: "trip.ride").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))

        // Closing the sheet keeps the ride: the strip is still there and opens it again.
        app.buttons["trip.close"].tap()
        XCTAssertTrue(card.waitForNonExistence(timeout: 5))
        XCTAssertTrue(strip.waitForExistence(timeout: 5))
        strip.tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5))

        app.buttons["trip.endRide"].tap()
        XCTAssertTrue(card.waitForNonExistence(timeout: 5))
        XCTAssertTrue(strip.waitForNonExistence(timeout: 5), "End ride ends the ride, and the strip goes")
    }
}
