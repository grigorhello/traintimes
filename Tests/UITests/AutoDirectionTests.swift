import XCTest

/// Automatic direction (TT-234, D116). Fixture runs have no location reader, so the Demo place stands the phone at the
/// route's To station: the app opens with the route turned round and "Now from Union" with Undo; Undo puts the route
/// back, and for the hour after it the app leaves the route alone, in a new launch too.
final class AutoDirectionTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// The fixture route is Oakville to Union; the Demo place is Union. The store is on device in fixture runs and the
    /// fixture clock stands still, so the Undo hour of the first launch still runs in the second, which passes no
    /// `noDirectionUndo`. That Undo hour stays on the simulator: a later test that needs a turn clears it with
    /// `LaunchArguments.noDirectionHolds`, as this one does first.
    @MainActor
    func testOpeningAtTheOtherStationTurnsTheRouteAndUndoHoldsForAnHour() {
        let app = XCUIApplication.onFixtures()
        // The capsule stays up for the test: on a slow runner reading it can take longer than its 5 s.
        app.launchEnvironment["TT_TOAST_SECONDS"] = "60"
        app.launchArguments += LaunchArguments.fixtureRoute + LaunchArguments.noRecents
            + LaunchArguments.demoPlace("UN") + LaunchArguments.noDirectionHolds
        app.launch()

        let from = app.buttons["schedule.from"]
        let to = app.buttons["schedule.to"]
        XCTAssertTrue(from.waitForExistence(timeout: Self.waitTime))
        expect(from, value: "Union")
        expect(to, value: "Oakville")

        // "Now from Union" with Undo, a second after the turn.
        let capsule = app.descendants(matching: .any).matching(identifier: "direction.capsule").firstMatch
        XCTAssertTrue(capsule.waitForExistence(timeout: Self.waitTime))
        let undo = app.buttons["direction.capsule.action"]
        XCTAssertTrue(undo.waitForExistence(timeout: Self.waitTime))
        XCTAssertEqual(undo.label, "Undo")

        undo.tap()
        expect(from, value: "Oakville")
        expect(to, value: "Union")
        // "Won’t switch by itself for an hour" takes the capsule's place, with no action.
        XCTAssertTrue(undo.waitForNonExistence(timeout: Self.waitTime))
        XCTAssertTrue(capsule.exists, "The line after Undo shows in the capsule's place")

        // A new launch inside the hour, still at Union, with no choice by hand and the setting on: only the Undo hour
        // keeps the route as it is.
        app.terminate()
        app.launchArguments = LaunchArguments.fixtureRoute + LaunchArguments.noRecents + LaunchArguments.demoPlace("UN")
            + LaunchArguments.noDirectionChoice + LaunchArguments.noDirectionOff
        app.launch()

        XCTAssertTrue(from.waitForExistence(timeout: Self.waitTime))
        expect(from, value: "Oakville")
        // A turn would come at once and its capsule a second later.
        XCTAssertFalse(capsule.waitForExistence(timeout: 5), "The Undo hour holds: no capsule")
        expect(from, value: "Oakville")
        expect(to, value: "Union")
    }

    /// The first turn brings the one-time strip (TT-236) under the day strip; OK closes it for good, so a new launch that
    /// turns the route again shows "Now from Union" alone.
    @MainActor
    func testTheFirstTurnShowsTheStripAndOKClosesItForGood() {
        let app = XCUIApplication.onFixtures()
        app.launchEnvironment["TT_TOAST_SECONDS"] = "60"
        app.launchArguments += LaunchArguments.fixtureRoute + LaunchArguments.noRecents
            + LaunchArguments.demoPlace("UN") + LaunchArguments.noDirectionHolds
        app.launch()

        let from = app.buttons["schedule.from"]
        XCTAssertTrue(from.waitForExistence(timeout: Self.waitTime))
        expect(from, value: "Union")
        let strip = app.descendants(matching: .any).matching(identifier: "direction.strip").firstMatch
        XCTAssertTrue(strip.waitForExistence(timeout: Self.waitTime))
        let ok = app.buttons["direction.strip.ok"]
        XCTAssertTrue(ok.exists)
        XCTAssertTrue(app.buttons["direction.strip.off"].exists)

        ok.tap()
        XCTAssertTrue(strip.waitForNonExistence(timeout: Self.waitTime))
        expect(from, value: "Union")

        // A new launch at Union turns the route again: the capsule shows, the strip does not. Only the strip's answer is
        // read from the device: the other holds stay cleared.
        app.terminate()
        app.launchArguments = LaunchArguments.fixtureRoute + LaunchArguments.noRecents + LaunchArguments.demoPlace("UN")
            + LaunchArguments.noDirectionUndo + LaunchArguments.noDirectionChoice + LaunchArguments.noDirectionOff
            + LaunchArguments.noDirectionTurns
        app.launch()

        XCTAssertTrue(from.waitForExistence(timeout: Self.waitTime))
        expect(from, value: "Union")
        let capsule = app.descendants(matching: .any).matching(identifier: "direction.capsule").firstMatch
        XCTAssertTrue(capsule.waitForExistence(timeout: Self.waitTime))
        XCTAssertFalse(strip.exists, "OK closed the strip for good")
    }

    /// Turn off on the strip turns only the setting off (TT-236): the route stays turned, and Settings › Automatic
    /// direction reads off. The "off" is cleared for the first launch, so it is read in a second launch that keeps it.
    @MainActor
    func testTurnOffOnTheStripTurnsTheSettingOff() {
        let app = XCUIApplication.onFixtures()
        app.launchEnvironment["TT_TOAST_SECONDS"] = "60"
        app.launchArguments += LaunchArguments.fixtureRoute + LaunchArguments.noRecents
            + LaunchArguments.demoPlace("UN") + LaunchArguments.noDirectionHolds
        app.launch()

        let from = app.buttons["schedule.from"]
        XCTAssertTrue(from.waitForExistence(timeout: Self.waitTime))
        expect(from, value: "Union")
        let strip = app.descendants(matching: .any).matching(identifier: "direction.strip").firstMatch
        XCTAssertTrue(strip.waitForExistence(timeout: Self.waitTime))
        app.buttons["direction.strip.off"].tap()
        XCTAssertTrue(strip.waitForNonExistence(timeout: Self.waitTime))
        expect(from, value: "Union")
        expect(app.buttons["schedule.to"], value: "Oakville")

        // The same place, with the stored "off": no turn, and the switch reads off.
        app.terminate()
        app.launchArguments = LaunchArguments.fixtureRoute + LaunchArguments.noRecents + LaunchArguments.demoPlace("UN")
            + LaunchArguments.noDirectionUndo + LaunchArguments.noDirectionChoice + LaunchArguments.noDirectionStrip
        app.launch()

        XCTAssertTrue(from.waitForExistence(timeout: Self.waitTime))
        expect(from, value: "Oakville")
        app.tabBars.buttons["Settings"].tap()
        let setting = app.switches["settings.autoDirection"]
        XCTAssertTrue(setting.waitForExistence(timeout: Self.waitTime))
        XCTAssertEqual(setting.value as? String, "0")
    }

    /// A query's first check can take over 5 s on a slow CI runner, so waits after a launch or a tap get 15 s.
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
