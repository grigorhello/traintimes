import XCTest

/// The Alerts tab as cards (TT-253, D129): the bell switches an alert off in place and on again, See trains lands on the
/// alert's own card in Schedule, its route and day (TT-255); the empty tab's next trains set the first alert with their bells and the card grows its days row;
/// with notifications off the card tops the tab. The app runs on the fixture schedule and alert server.
final class AlertsTabTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// The 7:32 AM train's bell on Schedule, then on Alerts: its card, the bell off and on in place, then See trains with
    /// Schedule left on Saturday lands on Today's 7:32 AM card.
    @MainActor
    func testTheBellSwitchesOffInPlaceAndSeeTrainsLandsOnTheCard() {
        let app = XCUIApplication.onFixtures()
        app.launchEnvironment["TT_NOTIFICATIONS"] = "allowed"
        app.launchArguments += LaunchArguments.fixtureRoute + LaunchArguments.noAlerts
        app.launch()

        let scheduleBell = app.buttons["schedule.bell.LW-0732-20261105"]
        XCTAssertTrue(scheduleBell.waitForExistence(timeout: 20))
        scheduleBell.tap()
        XCTAssertTrue(wait(for: scheduleBell, label: "Alert on for 7:32 AM train"))
        let today = app.buttons["schedule.day.0"]
        app.buttons["schedule.day.2"].tap()
        XCTAssertTrue(wait(for: today, selected: false))

        app.tabBars.buttons["Alerts"].tap()
        // Schedule stays in the tab view with its own card and bell, so look inside the Alerts tab only.
        let alerts = app.descendants(matching: .any).matching(identifier: "alerts.root").firstMatch
        let item = alerts.descendants(matching: .any).matching(identifier: "alerts.rule.LW-0732-20261105").firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 15))
        let card = item.buttons["alerts.card.LW-0732-20261105"]
        let bell = item.buttons["alerts.bell.LW-0732-20261105"]
        XCTAssertTrue(wait(for: card, labelContains: "Once"))
        XCTAssertTrue(wait(for: bell, label: "Alert on for 7:32 AM train"))

        bell.tap()
        XCTAssertTrue(wait(for: bell, label: "Alert for 7:32 AM train"))
        XCTAssertTrue(wait(for: card, labelContains: "Off"), "switched off in place")
        bell.tap()
        XCTAssertTrue(wait(for: bell, label: "Alert on for 7:32 AM train"))
        XCTAssertTrue(wait(for: card, labelContains: "Once"))

        item.buttons["alerts.seeTrains"].tap()
        XCTAssertTrue(wait(for: app.tabBars.buttons["Schedule"], selected: true))
        XCTAssertEqual(app.buttons["schedule.from"].value as? String, "Oakville")
        XCTAssertEqual(app.buttons["schedule.to"].value as? String, "Union")
        XCTAssertTrue(wait(for: today, selected: true), "the alert's day")
        let landed = app.descendants(matching: .any).matching(identifier: "schedule.card.LW-0732-20261105").firstMatch
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: landed)
        XCTAssertEqual(XCTWaiter.wait(for: [hittable], timeout: 15), .completed, "the card in view")
        XCTAssertGreaterThan(landed.frame.minY, today.frame.maxY, "below the day strip, not under the header")
    }

    /// With no alert, the next trains stand in; a bell there sets the first alert and its card grows the days row and See
    /// trains; back on the tab, the alert is a card of its own.
    @MainActor
    func testTheFirstAlertFromTheNextTrains() {
        let app = XCUIApplication.onFixtures()
        app.launchEnvironment["TT_NOTIFICATIONS"] = "allowed"
        app.launchArguments += LaunchArguments.fixtureRoute + LaunchArguments.noAlerts
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Alerts"].waitForExistence(timeout: 20))
        // Schedule has loaded today's trains before the tab opens.
        XCTAssertTrue(app.buttons["schedule.bell.LW-0732-20261105"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Alerts"].tap()
        XCTAssertTrue(app.staticTexts["Tap a bell to hear if a train is delayed or cancelled."].waitForExistence(timeout: 15))
        let empty = app.descendants(matching: .any).matching(identifier: "alerts.empty").firstMatch
        let bell = empty.buttons["alerts.next.bell.LW-0732-20261105"]
        XCTAssertTrue(bell.waitForExistence(timeout: 15))
        XCTAssertFalse(empty.buttons["alerts.seeTrains"].exists)
        bell.tap()
        XCTAssertTrue(empty.buttons["alerts.seeTrains"].waitForExistence(timeout: 15), "the card grows its days row")

        app.tabBars.buttons["Schedule"].tap()
        app.tabBars.buttons["Alerts"].tap()
        let item = app.descendants(matching: .any).matching(identifier: "alerts.rule.LW-0732-20261105").firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["Tap a bell to hear if a train is delayed or cancelled."].exists)
    }

    /// TT-169: with notifications off and an alert on, the card tops the tab and a bell nudges it instead of saving.
    @MainActor
    func testNotificationsOffShowsTheCard() {
        // The 7:32 AM train's alert is turned on from its bell with notifications allowed (a tap with them off saves
        // nothing, TT-190), then the app comes back with them off: the alert is kept, not delivered.
        let setup = XCUIApplication.onFixtures()
        setup.launchEnvironment["TT_NOTIFICATIONS"] = "allowed"
        setup.launchArguments += LaunchArguments.fixtureRoute + LaunchArguments.noAlerts
        setup.launch()
        let scheduleBell = setup.buttons["schedule.bell.LW-0732-20261105"]
        XCTAssertTrue(scheduleBell.waitForExistence(timeout: 20))
        scheduleBell.tap()
        XCTAssertTrue(wait(for: scheduleBell, label: "Alert on for 7:32 AM train"))
        setup.terminate()

        let app = XCUIApplication.onFixtures()
        app.launchEnvironment["TT_NOTIFICATIONS"] = "off"
        app.launchArguments += LaunchArguments.fixtureRoute
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Alerts"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Alerts"].tap()
        let warning = app.descendants(matching: .any).matching(identifier: "alerts.notificationsOff").firstMatch
        XCTAssertTrue(warning.waitForExistence(timeout: 15))
        XCTAssertTrue(warning.staticTexts["Notifications are off"].exists)
        XCTAssertTrue(warning.staticTexts["1 alert can’t reach you."].exists)
        XCTAssertTrue(app.buttons["alerts.turnOnInSettings"].exists)
        let item = app.descendants(matching: .any).matching(identifier: "alerts.rule.LW-0732-20261105").firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 15))
        item.buttons["alerts.bell.LW-0732-20261105"].tap()
        XCTAssertTrue(wait(for: item.buttons["alerts.card.LW-0732-20261105"], labelContains: "Once"), "still on: nothing saved")
    }

    private func wait(for element: XCUIElement, labelContains text: String) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", text), object: element)
        return XCTWaiter.wait(for: [expectation], timeout: 15) == .completed
    }

    private func wait(for element: XCUIElement, label: String) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: element)
        return XCTWaiter.wait(for: [expectation], timeout: 15) == .completed
    }

    private func wait(for element: XCUIElement, selected: Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == %@", NSNumber(value: selected)), object: element)
        return XCTWaiter.wait(for: [expectation], timeout: 15) == .completed
    }
}
