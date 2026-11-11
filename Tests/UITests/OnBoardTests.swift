import XCTest

/// TT-172: Demo trains › Ride plays a ride from Union to Clarkson. The ride strip on Schedule opens Trip details in ride
/// mode; closing the sheet keeps the ride, and End ride ends it and the strip goes. TT-177: Demo trains › Departure counts
/// down to the same train; its strip opens the departure card, and "I’m on board" turns it into the ride.
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

    @MainActor
    func testDemoDepartureCountsDownAndHandsOverIntoTheRide() {
        let app = XCUIApplication.onFixtures()
        app.launchArguments += LaunchArguments.fixtureRoute + ["-settings.demoTrains", "departure"]
        app.launch()

        let strip = app.descendants(matching: .any).matching(identifier: "schedule.departure").firstMatch
        XCTAssertTrue(strip.waitForExistence(timeout: 10))
        XCTAssertTrue(strip.label.contains("train"), strip.label)

        strip.tap()
        let card = app.descendants(matching: .any).matching(identifier: "trip.departure").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))

        app.buttons["trip.onboard"].tap()
        let ride = app.descendants(matching: .any).matching(identifier: "trip.ride").firstMatch
        XCTAssertTrue(ride.waitForExistence(timeout: 5))
        XCTAssertFalse(card.exists, "the departure card turned into the ride")

        // End ride stops the demo ride and closes the sheet; the countdown is back on Schedule.
        app.buttons["trip.endRide"].tap()
        XCTAssertTrue(ride.waitForNonExistence(timeout: 5))
        XCTAssertTrue(strip.waitForExistence(timeout: 5))
    }
}
