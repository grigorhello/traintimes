import XCTest

/// TT-172: Demo trains › Ride starts the ride from Union to Clarkson at once (TT-243: its question went with train
/// detection); the strip opens Trip details in ride mode, closing the sheet keeps the ride, and Done at your stop closes it
/// and the strip goes (TT-221). TT-177: Demo trains › Departure counts down to the same train; the Live Activity's link opens
/// its hero card (TT-205: Schedule has no countdown strip), and "I’m on board" turns it into the ride. TT-242 (D120): with
/// Demo trains › Depart › Automatic ride, the ride starts by itself when the demo phone leaves Union with the train, and not
/// when it stays. TT-243 (D120): Not on it ends that ride, and the one-time strip's OK and Turn off.
final class OnBoardTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testDemoRideStartsAtOnceAndDoneAtYourStopClosesIt() {
        let app = XCUIApplication.onFixtures()
        app.launchArguments += LaunchArguments.fixtureRoute + ["-settings.demoTrains", "ride"]
        app.launch()

        // No question first: the demo ride runs from launch, and its strip is on Schedule.
        let strip = app.descendants(matching: .any).matching(identifier: "schedule.ride").firstMatch
        XCTAssertTrue(strip.waitForExistence(timeout: 15))
        XCTAssertTrue(strip.label.contains("Clarkson"), strip.label)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "schedule.question").firstMatch.exists)
        strip.tap()
        let card = app.descendants(matching: .any).matching(identifier: "trip.ride").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15), "The strip opens Trip details in ride mode")
        XCTAssertTrue(app.buttons["trip.endRide"].exists, "A ride the rider started has End ride, not Not on it")

        // Closing the sheet keeps the ride: the strip opens it again.
        app.buttons["trip.close"].tap()
        XCTAssertTrue(card.waitForNonExistence(timeout: 15))
        XCTAssertTrue(strip.waitForExistence(timeout: 15))
        strip.tap()
        XCTAssertTrue(card.waitForExistence(timeout: 15))

        // TT-221: at Clarkson the button is Done (the demo reaches it about 2 min after launch, at 6×), and Done closes the
        // sheet and ends the ride. The departure test below covers End ride.
        let done = app.buttons["trip.endRide"]
        let isDone = NSPredicate(format: "label == %@", "Done")
        let reachesStop = XCTWaiter().wait(for: [expectation(for: isDone, evaluatedWith: done)], timeout: 300)
        XCTAssertEqual(reachesStop, .completed, done.label)
        // TT-223: 5 s later "Now" rolls into the arrival wish (the ride ends by itself 20 s after Clarkson at 6×). 15 s, as
        // slow runners need: at 12 s one read the wish just after the wait ran out.
        let wished = NSPredicate(format: "NOT (label CONTAINS %@)", "Now")
        let rollsIn = XCTWaiter().wait(for: [expectation(for: wished, evaluatedWith: card)], timeout: 15)
        XCTAssertEqual(rollsIn, .completed, card.label)
        XCTAssertFalse(card.label.contains("wish."), "The wish's words, not its key: \(card.label)")
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
        // The demo loops every 150 s; for the last 60 s of it the train has left and the sheet shows the trip instead.
        XCTAssertTrue(card.waitForExistence(timeout: 30))

        app.buttons["trip.onboard"].tap()
        let ride = app.descendants(matching: .any).matching(identifier: "trip.ride").firstMatch
        XCTAssertTrue(ride.waitForExistence(timeout: 15))
        XCTAssertFalse(card.exists, "the hero card turned into the ride")

        // End ride stops the demo ride.
        app.buttons["trip.endRide"].tap()
        XCTAssertTrue(ride.waitForNonExistence(timeout: 15))
    }

    /// TT-231 (D110): when the alerted train leaves with the app open on Schedule, its strip asks, and Yes starts the ride.
    /// The demo departure leaves at 5:16 PM on its clock, 90 s after launch at 10×, and asks for 60 s.
    @MainActor
    func testScheduleAsksOnBoardWhenTheDemoTrainLeaves() {
        let app = XCUIApplication.onFixtures()
        app.launchArguments += LaunchArguments.fixtureRoute + ["-settings.demoTrains", "departure"]
        app.launch()

        XCTAssertTrue(app.buttons["schedule.from"].waitForExistence(timeout: 15))
        let question = app.descendants(matching: .any).matching(identifier: "schedule.question").firstMatch
        XCTAssertFalse(question.exists, "not before the train leaves")
        XCTAssertTrue(question.waitForExistence(timeout: 130), "asks once the train has left")

        app.buttons["schedule.question.yes"].tap()
        let ride = app.descendants(matching: .any).matching(identifier: "trip.ride").firstMatch
        XCTAssertTrue(ride.waitForExistence(timeout: 15), "Yes lands in the ride")
        app.buttons["trip.endRide"].tap()
        XCTAssertTrue(ride.waitForNonExistence(timeout: 15))
    }

    /// TT-242 (D120): with Automatic ride on Boards the demo phone leaves Union with the train, and the ride starts by itself
    /// with no tap: ride mode opens over Schedule, and behind it the ride strip has taken the question's place. The train
    /// leaves 90 s after launch at 10×, and the start comes about 10 s later (the question shows only for those seconds, so
    /// it is not asserted).
    @MainActor
    func testDemoRideStartsByItselfWhenThePhoneLeavesWithTheTrain() {
        let app = XCUIApplication.onFixtures()
        app.launchArguments += LaunchArguments.fixtureRoute + ["-settings.demoTrains", "departure"]
            + LaunchArguments.demoAutoRide("boards")
        app.launch()

        XCTAssertTrue(app.buttons["schedule.from"].waitForExistence(timeout: 15))
        let strip = app.descendants(matching: .any).matching(identifier: "schedule.ride").firstMatch
        let ride = app.descendants(matching: .any).matching(identifier: "trip.ride").firstMatch
        XCTAssertFalse(strip.exists, "no ride before the train leaves")
        XCTAssertFalse(ride.exists)

        // Nothing is tapped until ride mode is up.
        XCTAssertTrue(ride.waitForExistence(timeout: 150), "the ride starts by itself and ride mode opens")

        // Closing the sheet keeps the ride: the strip is on Schedule.
        app.buttons["trip.close"].tap()
        XCTAssertTrue(ride.waitForNonExistence(timeout: 15))
        XCTAssertTrue(strip.waitForExistence(timeout: 15), "the ride strip on Schedule")
        XCTAssertTrue(strip.label.contains("Clarkson"), strip.label)
    }

    /// TT-242 (D120): with Automatic ride on Stays the demo phone stays at Union while the train moves off: Schedule asks
    /// "On board?" once the train has left, and no ride starts.
    @MainActor
    func testDemoRideDoesNotStartWhenThePhoneStays() {
        let app = XCUIApplication.onFixtures()
        app.launchArguments += LaunchArguments.fixtureRoute + ["-settings.demoTrains", "departure"]
            + LaunchArguments.demoAutoRide("stays")
        app.launch()

        XCTAssertTrue(app.buttons["schedule.from"].waitForExistence(timeout: 15))
        let question = app.descendants(matching: .any).matching(identifier: "schedule.question").firstMatch
        XCTAssertTrue(question.waitForExistence(timeout: 130), "asks once the train has left")

        // With Boards the ride starts about 10 s after the train leaves; Stays is watched for three times as long.
        let strip = app.descendants(matching: .any).matching(identifier: "schedule.ride").firstMatch
        XCTAssertFalse(strip.waitForExistence(timeout: 30), "no ride starts: the phone stayed at Union")
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "trip.ride").firstMatch.exists)
    }

    /// TT-243 (D120): the Boards demo's ride starts by itself, and Not on it on the ride screen ends it: the sheet closes, the
    /// ride strip goes and the question does not come back for that train. The one-time strip then says rides start by
    /// themselves, and OK closes it. Not on it shows for the ride's first 10 min, 60 s at the demo's 10×, so it is tapped at
    /// once.
    @MainActor
    func testNotOnItEndsARideThatStartedByItselfAndOKClosesTheStrip() {
        let app = launchBoards()
        let ride = app.descendants(matching: .any).matching(identifier: "trip.ride").firstMatch
        XCTAssertTrue(ride.waitForExistence(timeout: 150), "the ride starts by itself and ride mode opens")
        notOnIt(app, ride: ride)

        let autoStrip = app.descendants(matching: .any).matching(identifier: "autoride.strip").firstMatch
        XCTAssertTrue(autoStrip.waitForExistence(timeout: 15), "the one-time strip once the ride is over")
        app.buttons["autoride.strip.ok"].tap()
        XCTAssertTrue(autoStrip.waitForNonExistence(timeout: 15))
        let question = app.descendants(matching: .any).matching(identifier: "schedule.question").firstMatch
        XCTAssertFalse(question.waitForExistence(timeout: 10), "Not on it declined that train: nothing asks about it")
    }

    /// TT-243 (D120): the one-time strip's Turn off turns Automatic ride off, and its Settings switch reads off. The "off" is
    /// cleared for the first launch, so it is read in a second launch that keeps it, as `AutoDirectionTests` does; the
    /// switch then turns it on again (a demo mode needs no location), so nothing is left on the simulator.
    @MainActor
    func testTheStripsTurnOffTurnsAutomaticRideOff() {
        let app = launchBoards()
        let ride = app.descendants(matching: .any).matching(identifier: "trip.ride").firstMatch
        XCTAssertTrue(ride.waitForExistence(timeout: 150), "the ride starts by itself and ride mode opens")
        notOnIt(app, ride: ride)

        let autoStrip = app.descendants(matching: .any).matching(identifier: "autoride.strip").firstMatch
        XCTAssertTrue(autoStrip.waitForExistence(timeout: 15))
        app.buttons["autoride.strip.off"].tap()
        XCTAssertTrue(autoStrip.waitForNonExistence(timeout: 15))

        app.terminate()
        // No demo departure plays now; the Automatic ride mode alone makes the switch read the stored "off".
        app.launchArguments = LaunchArguments.fixtureRoute + LaunchArguments.demoAutoRide("boards")
            + LaunchArguments.noAutoRideStrip + LaunchArguments.noAutoRideNotOnIt
        app.launch()
        XCTAssertTrue(app.buttons["schedule.from"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Settings"].tap()
        let setting = app.switches["settings.autoRide"]
        XCTAssertTrue(setting.waitForExistence(timeout: 15))
        XCTAssertEqual(setting.value as? String, "0")

        setting.tap()
        XCTAssertTrue(waitForValue(setting, "1"), "the switch turns it on again")
    }

    /// Waits up to 15 s for a switch to read `value`.
    @MainActor
    private func waitForValue(_ element: XCUIElement, _ value: String) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        return XCTWaiter.wait(for: [expectation], timeout: 15) == .completed
    }

    /// The demo departure with Automatic ride on Boards, nothing held back by an earlier run, on Schedule.
    @MainActor
    private func launchBoards() -> XCUIApplication {
        let app = XCUIApplication.onFixtures()
        app.launchArguments += LaunchArguments.fixtureRoute + ["-settings.demoTrains", "departure"]
            + LaunchArguments.demoAutoRide("boards") + LaunchArguments.noAutoRideHolds
        app.launch()
        XCTAssertTrue(app.buttons["schedule.from"].waitForExistence(timeout: 15))
        return app
    }

    /// Not on it on the open ride screen: the sheet closes and the ride strip goes.
    @MainActor
    private func notOnIt(_ app: XCUIApplication, ride: XCUIElement) {
        let notOnIt = app.buttons["trip.notOnIt"]
        XCTAssertTrue(notOnIt.waitForExistence(timeout: 5), "Not on it in End ride's place")
        XCTAssertFalse(app.buttons["trip.endRide"].exists)
        notOnIt.tap()
        XCTAssertTrue(ride.waitForNonExistence(timeout: 15), "Not on it closes the sheet")
        let strip = app.descendants(matching: .any).matching(identifier: "schedule.ride").firstMatch
        XCTAssertTrue(strip.waitForNonExistence(timeout: 15), "and ends the ride")
    }
}
