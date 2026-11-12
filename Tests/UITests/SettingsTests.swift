import XCTest

final class SettingsTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// The main view's glass switches change Appearance and Time format in one tap, and Notifications, About and Testing open
    /// and close (TT-105, TT-168).
    @MainActor
    func testChangeAppearanceAndOpenThePages() {
        let app = XCUIApplication.onFixtures()
        // Not asked yet, whatever an earlier test answered in the iOS dialog (TT-142).
        app.launchEnvironment["TT_NOTIFICATIONS"] = "notAsked"
        // Start from the defaults whatever an earlier run stored.
        app.launchArguments += ["-settings.appearance", "system", "-settings.timeFormat", "device"] + LaunchArguments.noAlerts
        app.launch()

        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["settings.title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings.appearance.system"].isSelected)
        XCTAssertTrue(app.buttons["settings.timeFormat.device"].isSelected)

        app.buttons["settings.appearance.dark"].tap()
        XCTAssertTrue(app.buttons["settings.appearance.dark"].isSelected)
        XCTAssertFalse(app.buttons["settings.appearance.system"].isSelected)
        app.buttons["settings.timeFormat.24h"].tap()
        XCTAssertTrue(app.buttons["settings.timeFormat.24h"].isSelected)

        // Leave the simulator on the defaults for the next run.
        app.buttons["settings.appearance.system"].tap()
        app.buttons["settings.timeFormat.device"].tap()
        XCTAssertTrue(app.buttons["settings.appearance.system"].isSelected)

        // The app never asks before an alert is set or "Turn on notifications" is tapped (TT-142, TT-168), so a fresh install
        // reads Off with a grey dot, and the page offers to turn them on.
        let notifications = app.buttons["settings.notifications"]
        XCTAssertTrue(notifications.waitForExistence(timeout: 5))
        XCTAssertTrue(notifications.label.contains("Off"))
        notifications.tap()
        XCTAssertTrue(app.staticTexts["Not turned on yet"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings.notifications.turnOn"].exists)
        XCTAssertTrue(app.buttons["settings.myAlerts"].label.contains("0"))
        // The tab bar stays on a pushed page.
        XCTAssertTrue(app.tabBars.buttons["Settings"].exists)
        app.buttons["settings.back"].tap()
        XCTAssertTrue(app.staticTexts["settings.title"].waitForExistence(timeout: 5))

        app.buttons["settings.about"].tap()
        XCTAssertTrue(app.staticTexts["Train Times"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings.privacy"].exists)
        XCTAssertTrue(app.buttons["settings.scheduleData"].exists)
        XCTAssertTrue(app.buttons["settings.officialUpdates"].exists)
        app.buttons["settings.back"].tap()
        XCTAssertTrue(app.staticTexts["settings.title"].waitForExistence(timeout: 5))

        app.buttons["settings.testing"].tap()
        XCTAssertTrue(app.staticTexts["Demo trains"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings.demoTrains.off"].isSelected)
        app.buttons["settings.back"].tap()
        XCTAssertTrue(app.staticTexts["settings.title"].waitForExistence(timeout: 5))
    }

    /// "My alerts" on the Notifications page switches to the Alerts tab (TT-168).
    @MainActor
    func testMyAlertsOpensTheAlertsTab() {
        let app = XCUIApplication.onFixtures()
        app.launchEnvironment["TT_NOTIFICATIONS"] = "allowed"
        app.launchArguments += LaunchArguments.noAlerts
        app.launch()

        app.tabBars.buttons["Settings"].tap()
        app.buttons["settings.notifications"].tap()
        XCTAssertTrue(app.staticTexts["Notifications are on"].waitForExistence(timeout: 5))
        app.buttons["settings.myAlerts"].tap()
        XCTAssertTrue(app.staticTexts["Next trains"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.tabBars.buttons["Alerts"].isSelected)
    }

    /// Settings › Testing › Demo trains (D49), in Debug and TestFlight builds: Offline shows the cached timetable with the
    /// Offline status row on Schedule, and the control reads Offline. Launched with the stored choice as an argument, so
    /// nothing is left on the simulator for the next run.
    @MainActor
    func testDemoTrainsOfflineShowsTheOfflineRow() {
        let app = XCUIApplication.onFixtures()
        app.launchArguments += LaunchArguments.fixtureRoute + ["-settings.demoTrains", "offline"]
        app.launch()

        XCTAssertTrue(app.buttons["schedule.from"].waitForExistence(timeout: 10))
        let offline = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Offline · last updated")).firstMatch
        XCTAssertTrue(offline.waitForExistence(timeout: 10))

        app.tabBars.buttons["Settings"].tap()
        let testing = app.buttons["settings.testing"]
        XCTAssertTrue(testing.waitForExistence(timeout: 5))
        XCTAssertTrue(testing.label.contains("Offline"), "The Testing row says what is on")
        testing.tap()
        XCTAssertTrue(app.staticTexts["Demo trains"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings.demoTrains.offline"].isSelected)
        XCTAssertFalse(app.buttons["settings.demoTrains.off"].isSelected)
    }

    /// Settings › Testing › Mock time (TT-158, D51), in Debug and TestFlight builds: Mock time with a quick choice moves
    /// Schedule's clock (the 7:32 AM train is no longer "in 11 min"), and Reset brings the real time back.
    @MainActor
    func testMockTimeMovesTheScheduleClockAndResetBringsItBack() {
        let app = XCUIApplication.onFixtures()
        app.launchArguments += LaunchArguments.fixtureRoute
        app.launch()

        let card = app.descendants(matching: .any).matching(identifier: "schedule.card.LW-0732-20261105").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        XCTAssertTrue(card.label.contains("in 11 min"), "The fixture clock is 7:21 AM")

        // Tapping stores Mock time on the simulator, so a failure part way still turns it off for the next test.
        addTeardownBlock {
            app.tabBars.buttons["Settings"].tap()
            let testing = app.buttons["settings.testing"]
            if testing.exists { testing.tap() }
            let reset = app.buttons["settings.testing.reset"]
            if reset.waitForExistence(timeout: 2), reset.isHittable { reset.tap() }
        }
        app.tabBars.buttons["Settings"].tap()
        app.buttons["settings.testing"].tap()
        let mockTime = app.switches["settings.mockTime"]
        XCTAssertTrue(mockTime.waitForExistence(timeout: 5))
        // The switch is labelled, so its element spans the row: tap at the trailing edge, where the switch is.
        mockTime.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        let dayChange = app.buttons["settings.mockTime.dayChange"]
        XCTAssertTrue(dayChange.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["settings.mockTime.picker"].exists)
        dayChange.tap()
        XCTAssertEqual(app.switches["settings.mockTime"].value as? String, "1")

        app.tabBars.buttons["Schedule"].tap()
        wait(for: [expectation(for: NSPredicate(format: "NOT (label CONTAINS 'in 11 min')"), evaluatedWith: card)], timeout: 10)

        // The Settings tab still shows the Testing page; Reset turns Mock time off and goes back to the real time.
        app.tabBars.buttons["Settings"].tap()
        let reset = app.buttons["settings.testing.reset"]
        XCTAssertTrue(reset.waitForExistence(timeout: 5))
        reset.tap()
        XCTAssertEqual(app.switches["settings.mockTime"].value as? String, "0")
        XCTAssertFalse(app.buttons["settings.mockTime.dayChange"].exists)

        app.tabBars.buttons["Schedule"].tap()
        wait(for: [expectation(for: NSPredicate(format: "label CONTAINS 'in 11 min'"), evaluatedWith: card)], timeout: 10)
    }
}
