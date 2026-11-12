import XCTest

/// TT-172, TT-175: Demo trains › Ride first asks on Schedule "On the 5:13 PM train?" (about 25 s after launch), and its Yes
/// starts the ride from Union to Clarkson and opens Trip details in ride mode. Closing the sheet keeps the ride and the
/// strip opens it again; End ride ends it and the strip goes. TT-177: Demo trains › Departure counts down to the same
/// train; its strip opens the departure card, and "I’m on board" turns it into the ride.
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
        XCTAssertTrue(card.waitForExistence(timeout: 15), "Yes opens Trip details in ride mode")

        // Closing the sheet keeps the ride: the strip has taken the question's place and opens it again.
        app.buttons["trip.close"].tap()
        XCTAssertTrue(card.waitForNonExistence(timeout: 15))
        XCTAssertTrue(strip.waitForExistence(timeout: 15))
        XCTAssertTrue(strip.label.contains("On board"), strip.label)
        XCTAssertFalse(question.exists)
        strip.tap()
        XCTAssertTrue(card.waitForExistence(timeout: 15))

        app.buttons["trip.endRide"].tap()
        XCTAssertTrue(card.waitForNonExistence(timeout: 15))
        XCTAssertTrue(strip.waitForNonExistence(timeout: 15), "End ride ends the ride, and the strip goes")
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
        // The strip is away for 12 s of each 102 s loop, while the demo train reads Departed.
        XCTAssertTrue(strip.waitForExistence(timeout: 15))
    }
}
