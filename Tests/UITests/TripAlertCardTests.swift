import XCTest

/// Trip details alert-first (TT-254, D129): "Alert me" on a train with no alert brings the alert card on top and the bar
/// goes; the switch turns the alert off and on in place; a day mark makes the one-day alert repeat; Remove alert closes the
/// sheet, and Schedule (or the Alerts tab, when the sheet came from there) says "Alert removed" with Undo. With
/// notifications off "Alert me" saves nothing and the capsule in the sheet says so.
final class TripAlertCardTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testAlertMeBringsTheCardAndTheSwitchAndADaySaveInPlace() {
        let app = XCUIApplication.onFixtures()
        app.launchEnvironment["TT_NOTIFICATIONS"] = "allowed"
        app.launchArguments += LaunchArguments.fixtureRoute + LaunchArguments.noAlerts
        app.launch()
        openTrip(app)

        let alert = app.buttons["trip.alert"]
        XCTAssertTrue(alert.waitForExistence(timeout: 15))
        XCTAssertEqual(alert.label, "Alert me")
        alert.tap()
        XCTAssertTrue(card(app).waitForExistence(timeout: 15), "the card arrives on top")
        XCTAssertTrue(alert.waitForNonExistence(timeout: 15), "no bar while the train has an alert")
        XCTAssertTrue(app.staticTexts["Once, today"].exists)

        let toggle = app.switches["trip.alertSwitch"]
        XCTAssertEqual(toggle.value as? String, "1")
        toggle.tap()
        XCTAssertTrue(wait(for: toggle, value: "0"), "switched off in place")
        XCTAssertTrue(card(app).exists, "the card stays")
        toggle.tap()
        XCTAssertTrue(wait(for: toggle, value: "1"))

        let monday = app.buttons["trip.alertDay.1"]
        XCTAssertFalse(monday.isSelected)
        monday.tap()
        XCTAssertTrue(wait(for: monday, selected: true))
        XCTAssertTrue(app.staticTexts["Once, today"].waitForNonExistence(timeout: 15), "it repeats now")
        XCTAssertTrue(app.buttons["trip.alertDay.4"].isSelected, "and keeps its own day")

        app.buttons["trip.close"].tap()
        XCTAssertTrue(sheet(app).waitForNonExistence(timeout: 15))
        XCTAssertTrue(wait(for: app.buttons["schedule.bell.LW-0732-20261105"], label: "Alert on for 7:32 AM train"))
    }

    /// Opened from Schedule, Remove alert closes the sheet and Schedule says "Alert removed"; Undo brings the alert back.
    @MainActor
    func testRemoveAlertClosesTheSheetAndScheduleOffersUndo() {
        let app = XCUIApplication.onFixtures()
        app.launchEnvironment["TT_NOTIFICATIONS"] = "allowed"
        app.launchEnvironment["TT_TOAST_SECONDS"] = "60"
        app.launchArguments += LaunchArguments.fixtureRoute + LaunchArguments.noAlerts
        app.launch()

        let bell = app.buttons["schedule.bell.LW-0732-20261105"]
        XCTAssertTrue(bell.waitForExistence(timeout: 20))
        bell.tap()
        XCTAssertTrue(wait(for: bell, label: "Alert on for 7:32 AM train"))
        openTrip(app)
        XCTAssertTrue(card(app).waitForExistence(timeout: 15), "alert first")
        XCTAssertFalse(app.buttons["trip.alert"].exists)

        app.buttons["trip.removeAlert"].tap()
        XCTAssertTrue(sheet(app).waitForNonExistence(timeout: 15), "the sheet closes")
        XCTAssertTrue(app.staticTexts["Alert removed"].waitForExistence(timeout: 15))
        XCTAssertTrue(wait(for: bell, label: "Alert for 7:32 AM train"))
        undo(app).tap()
        XCTAssertTrue(wait(for: bell, label: "Alert on for 7:32 AM train"), "Undo brings it back")
    }

    /// Opened from the Alerts tab, Remove alert closes the sheet and the tab says "Alert removed" with Undo.
    @MainActor
    func testRemoveAlertFromTheAlertsTab() {
        let app = XCUIApplication.onFixtures()
        app.launchEnvironment["TT_NOTIFICATIONS"] = "allowed"
        app.launchEnvironment["TT_TOAST_SECONDS"] = "60"
        app.launchArguments += LaunchArguments.fixtureRoute + LaunchArguments.noAlerts
        app.launch()

        let bell = app.buttons["schedule.bell.LW-0732-20261105"]
        XCTAssertTrue(bell.waitForExistence(timeout: 20))
        bell.tap()
        XCTAssertTrue(wait(for: bell, label: "Alert on for 7:32 AM train"))
        app.tabBars.buttons[MyTrainsCopy.tab].tap()
        let alerts = app.descendants(matching: .any).matching(identifier: "alerts.root").firstMatch
        let item = alerts.descendants(matching: .any).matching(identifier: "alerts.rule.LW-0732-20261105").firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 15))
        item.buttons["alerts.card.LW-0732-20261105"].tap()
        XCTAssertTrue(card(app).waitForExistence(timeout: 15), "alert first")

        app.buttons["trip.removeAlert"].tap()
        XCTAssertTrue(sheet(app).waitForNonExistence(timeout: 15), "the sheet closes")
        XCTAssertTrue(app.staticTexts["Alert removed"].waitForExistence(timeout: 15))
        XCTAssertTrue(item.waitForNonExistence(timeout: 15), "the tab's card shuts")
        undo(app).tap()
        XCTAssertTrue(item.waitForExistence(timeout: 15), "Undo brings it back")
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
        XCTAssertTrue(alert.waitForExistence(timeout: 15))
        alert.tap()
        XCTAssertTrue(app.staticTexts["Notifications are off"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.buttons["alert.capsule.action"].label, "Turn on")
        XCTAssertEqual(alert.label, "Alert me", "nothing saved")
        XCTAssertFalse(card(app).exists)
    }

    /// The 7:32 AM card's Trip details.
    @MainActor
    private func openTrip(_ app: XCUIApplication) {
        let card = app.descendants(matching: .any).matching(identifier: "schedule.card.LW-0732-20261105").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20))
        card.tap()
        XCTAssertTrue(sheet(app).waitForExistence(timeout: 15))
    }

    /// The capsule's Undo: Schedule's capsule stays in the tab view's tree under the Alerts tab, so the action is told by its
    /// word.
    @MainActor
    private func undo(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(identifier: "alert.capsule.action").matching(NSPredicate(format: "label == 'Undo'")).firstMatch
    }

    @MainActor
    private func sheet(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "sheet.tripDetails").firstMatch
    }

    @MainActor
    private func card(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "trip.alertCard").firstMatch
    }

    private func wait(for element: XCUIElement, label: String) -> Bool {
        wait(for: element, NSPredicate(format: "label == %@", label))
    }

    private func wait(for element: XCUIElement, value: String) -> Bool {
        wait(for: element, NSPredicate(format: "value == %@", value))
    }

    private func wait(for element: XCUIElement, selected: Bool) -> Bool {
        wait(for: element, NSPredicate(format: "isSelected == %@", NSNumber(value: selected)))
    }

    private func wait(for element: XCUIElement, _ predicate: NSPredicate) -> Bool {
        XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 15) == .completed
    }
}
