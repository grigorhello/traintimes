import XCTest

/// The one-tap bell (TT-141) and its glass capsule (TT-191): with notifications allowed a tap turns the alert on, the capsule
/// confirms it with Repeat and the bell reads On; Repeat grows the capsule into the day panel, a day tile saves, the tick
/// closes it; the next tap turns the repeating alert off on all days. Without permission the tap opens the alert setup sheet.
final class AlertBellTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testBellRepeatDayTileAndClose() {
        let app = XCUIApplication.onFixtures()
        app.launchEnvironment["TT_NOTIFICATIONS"] = "allowed"
        // The first UI test of a run launches a cold simulator, and on a slow runner reading the capsule can take longer
        // than its 5 s, so it stays up for the test, and the waits below allow for such a runner (PR #90: the bell's label
        // took more than 10 s to read).
        app.launchEnvironment["TT_TOAST_SECONDS"] = "60"
        app.launchArguments += LaunchArguments.fixtureRoute + LaunchArguments.noAlerts
        app.launch()

        let bell = app.buttons["schedule.bell.LW-0732-20261105"]
        XCTAssertTrue(bell.waitForExistence(timeout: 20))
        XCTAssertEqual(bell.label, "Alert for 7:32 AM train")

        bell.tap()
        XCTAssertTrue(app.staticTexts["Alert on · 7:32 AM"].waitForExistence(timeout: 30))
        XCTAssertTrue(wait(for: bell, label: "Alert on for 7:32 AM train"))
        let repeatButton = app.buttons["alert.capsule.action"]
        XCTAssertTrue(repeatButton.waitForExistence(timeout: 15))
        XCTAssertEqual(repeatButton.label, "Repeat")

        repeatButton.tap()
        let days = app.staticTexts["alert.panel.days"]
        XCTAssertTrue(days.waitForExistence(timeout: 15))
        XCTAssertTrue(wait(for: days, label: "7:32 AM · Mon to Fri"))

        app.buttons["alert.day.6"].tap()
        XCTAssertTrue(wait(for: days, label: "7:32 AM · Mon to Sat"))

        app.buttons["alert.panel.done"].tap()
        XCTAssertTrue(days.waitForNonExistence(timeout: 15))
        XCTAssertTrue(wait(for: bell, label: "Alert on for 7:32 AM train"))

        bell.tap()
        XCTAssertTrue(app.staticTexts["Alert off · 7:32 AM, all days"].waitForExistence(timeout: 30))
        XCTAssertTrue(wait(for: bell, label: "Alert for 7:32 AM train"))
        XCTAssertEqual(app.buttons["alert.capsule.action"].label, "Undo")
    }

    @MainActor
    func testBellWithoutPermissionOpensAlertSetup() {
        let app = XCUIApplication.onFixtures()
        app.launchEnvironment["TT_NOTIFICATIONS"] = "notAsked"
        app.launchArguments += LaunchArguments.fixtureRoute + LaunchArguments.noAlerts
        app.launch()

        let bell = app.buttons["schedule.bell.LW-0732-20261105"]
        XCTAssertTrue(bell.waitForExistence(timeout: 10))
        bell.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "sheet.alertSetup").firstMatch.waitForExistence(timeout: 5))
    }

    private func wait(for element: XCUIElement, label: String) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: element)
        return XCTWaiter.wait(for: [expectation], timeout: 30) == .completed
    }
}
