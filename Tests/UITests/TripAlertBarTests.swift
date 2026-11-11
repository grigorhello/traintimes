import XCTest

/// Trip details' alert bar (TT-192, D77): "Alert me" turns the alert on in place and the sheet stays; "Alert on" with
/// Repeat beside it; Repeat opens the day panel inside the sheet, which saves a day and closes on its tick; "Alert on"
/// turns the alert off. With notifications off a tap saves nothing and the capsule in the sheet says so.
final class TripAlertBarTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testAlertMeTurnsOnInPlaceRepeatOpensThePanelAndAlertOnTurnsOff() {
        let app = XCUIApplication.onFixtures()
        app.launchEnvironment["TT_NOTIFICATIONS"] = "allowed"
        app.launchArguments += LaunchArguments.fixtureRoute + LaunchArguments.noAlerts
        app.launch()
        openTrip(app)

        let alert = app.buttons["trip.alert"]
        XCTAssertEqual(alert.label, "Alert me")
        alert.tap()
        XCTAssertTrue(wait(for: alert, label: "Alert on"))
        let sheet = app.descendants(matching: .any).matching(identifier: "sheet.tripDetails").firstMatch
        XCTAssertTrue(sheet.exists, "the sheet stays")
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "sheet.alertSetup").firstMatch.exists)

        let repeatButton = app.buttons["trip.repeat"]
        XCTAssertTrue(repeatButton.waitForExistence(timeout: 15))
        XCTAssertTrue(wait(for: repeatButton, label: "Repeat"))
        // Repeat ignores taps for its first 0.7 s.
        sleep(1)
        repeatButton.tap()
        let days = app.staticTexts["alert.panel.days"]
        XCTAssertTrue(days.waitForExistence(timeout: 15))
        XCTAssertTrue(wait(for: days, label: "7:32 AM · Mon to Fri"))
        app.buttons["alert.day.6"].tap()
        XCTAssertTrue(wait(for: days, label: "7:32 AM · Mon to Sat"))
        app.buttons["alert.panel.done"].tap()
        XCTAssertTrue(days.waitForNonExistence(timeout: 15))
        XCTAssertTrue(wait(for: repeatButton, label: "Mon to Sat"))

        alert.tap()
        XCTAssertTrue(wait(for: alert, label: "Alert me"))
        app.buttons["trip.close"].tap()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 15))
        let bell = app.buttons["schedule.bell.LW-0732-20261105"]
        XCTAssertTrue(wait(for: bell, label: "Alert for 7:32 AM train"))
    }

    /// With notifications off, "Alert me" saves nothing and the capsule in the sheet says "Notifications are off".
    @MainActor
    func testNotificationsOffShowsTheCapsuleInTheSheet() {
        let app = XCUIApplication.onFixtures()
        app.launchEnvironment["TT_NOTIFICATIONS"] = "off"
        app.launchEnvironment["TT_TOAST_SECONDS"] = "60"
        app.launchArguments += LaunchArguments.fixtureRoute + LaunchArguments.noAlerts
        app.launch()
        openTrip(app)

        let alert = app.buttons["trip.alert"]
        alert.tap()
        XCTAssertTrue(app.staticTexts["Notifications are off"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.buttons["alert.capsule.action"].label, "Turn on")
        XCTAssertEqual(alert.label, "Alert me", "nothing saved")
    }

    /// The 7:32 AM card's Trip details, with its bar.
    @MainActor
    private func openTrip(_ app: XCUIApplication) {
        let card = app.descendants(matching: .any).matching(identifier: "schedule.card.LW-0732-20261105").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20))
        card.tap()
        XCTAssertTrue(app.buttons["trip.alert"].waitForExistence(timeout: 15))
    }

    private func wait(for element: XCUIElement, label: String) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: 15) == .completed
    }
}
