import XCTest

/// TT-172, TT-175: Demo trains › Ride first asks on Schedule "On the train to Clarkson?" (about 25 s after launch), and its
/// Yes starts the ride from Union to Clarkson and opens Trip details in ride mode. Closing the sheet keeps the ride and the
/// strip opens it again; Done at your stop closes it and the strip goes (TT-221). TT-177: Demo trains › Departure counts
/// down to the same train; the Live Activity's link opens its hero card (TT-205: Schedule has no countdown strip), and
/// "I’m on board" turns it into the ride.
final class OnBoardTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testDemoQuestionYesStartsTheRideAndDoneAtYourStopClosesIt() {
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
        XCTAssertTrue(strip.label.contains("Clarkson"), strip.label)
        XCTAssertFalse(question.exists)
        strip.tap()
        XCTAssertTrue(card.waitForExistence(timeout: 15))

        // TT-221: at Clarkson the button is Done (the demo reaches it about 3 min after the Yes, at 6×), and Done closes the
        // sheet and ends the ride. The departure test below covers End ride.
        let done = app.buttons["trip.endRide"]
        let isDone = NSPredicate(format: "label == %@", "Done")
        let reachesStop = XCTWaiter().wait(for: [expectation(for: isDone, evaluatedWith: done)], timeout: 300)
        XCTAssertEqual(reachesStop, .completed, done.label)
        // TT-223: 5 s later "Now" rolls into the arrival wish (the ride ends by itself 20 s after Clarkson at 6×).
        let wished = NSPredicate(format: "NOT (label CONTAINS %@)", "Now")
        let rollsIn = XCTWaiter().wait(for: [expectation(for: wished, evaluatedWith: card)], timeout: 12)
        XCTAssertEqual(rollsIn, .completed, card.label)
        done.tap()
        XCTAssertTrue(card.waitForNonExistence(timeout: 15), "Done closes the ride screen")
        XCTAssertTrue(strip.waitForNonExistence(timeout: 15), "Done ends the ride, and the strip goes")
    }

    @MainActor
    func testDemoDepartureCountsDownAndHandsOverIntoTheRide() {
        let app = XCUIApplication.onFixtures()
        app.launchArguments += LaunchArguments.fixtureRoute + ["-settings.demoTrains", "departure"]
        app.launch()

        XCTAssertTrue(app.buttons["schedule.from"].waitForExistence(timeout: 15))
        XCTAssertFalse(
            app.descendants(matching: .any).matching(identifier: "schedule.departure").firstMatch.exists,
            "no countdown strip on Schedule (D93)"
        )

        // The departure's Live Activity link, as a tap on the Lock Screen card sends it.
        app.open(URL(string: "traintimes://departure")!)
        // iOS may ask first whether to open the link in the app.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.buttons["Open"].waitForExistence(timeout: 3) { springboard.buttons["Open"].tap() }
        let card = app.descendants(matching: .any).matching(identifier: "trip.departure").firstMatch
        // The demo loops every 102 s and reads Departed for 12 s of it, when the sheet shows the trip instead.
        XCTAssertTrue(card.waitForExistence(timeout: 30))

        app.buttons["trip.onboard"].tap()
        let ride = app.descendants(matching: .any).matching(identifier: "trip.ride").firstMatch
        XCTAssertTrue(ride.waitForExistence(timeout: 15))
        XCTAssertFalse(card.exists, "the hero card turned into the ride")

        // End ride stops the demo ride.
        app.buttons["trip.endRide"].tap()
        XCTAssertTrue(ride.waitForNonExistence(timeout: 15))
    }
}
