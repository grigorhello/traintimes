import XCTest

/// The one-tap bell (TT-141): with notifications allowed a tap arms the alert, the toast confirms it and the bell reads
/// On; a second tap turns it off. Without permission the tap opens the alert setup sheet.
final class AlertBellTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testBellArmsThenTurnsOffTheAlert() {
        let app = XCUIApplication.onFixtures()
        app.launchEnvironment["TT_NOTIFICATIONS"] = "allowed"
        // The first UI test of a run launches a cold simulator, and on a slow runner reading the toast can take longer
        // than its 2.5 s, so the toast stays up for the test, and the waits below allow for such a runner (PR #90: the
        // bell's label took more than 10 s to read).
        app.launchEnvironment["TT_TOAST_SECONDS"] = "60"
        app.launchArguments += LaunchArguments.fixtureRoute + LaunchArguments.noAlerts
        app.launch()

        let bell = app.buttons["schedule.bell.LW-0732-20261105"]
        XCTAssertTrue(bell.waitForExistence(timeout: 20))
        XCTAssertEqual(bell.label, "Alert for 7:32 AM train")

        bell.tap()
        XCTAssertTrue(app.staticTexts["Alert on for the 7:32 AM train"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["toast.action"].waitForExistence(timeout: 15))
        XCTAssertTrue(wait(for: bell, label: "Alert on for 7:32 AM train"))

        bell.tap()
        XCTAssertTrue(app.staticTexts["Alert off"].waitForExistence(timeout: 30))
        XCTAssertTrue(wait(for: bell, label: "Alert for 7:32 AM train"))
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
