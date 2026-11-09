import XCTest

final class SettingsTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Settings shows the permission in words and changes Appearance and Time format (TT-105).
    @MainActor
    func testChangeAppearanceAndTimeFormat() {
        let app = XCUIApplication.onFixtures()
        // Not asked yet, whatever an earlier test answered in the iOS dialog (TT-142).
        app.launchEnvironment["TT_NOTIFICATIONS"] = "notAsked"
        // Start from the defaults whatever an earlier run stored.
        app.launchArguments += ["-settings.appearance", "system", "-settings.timeFormat", "device"]
        app.launch()

        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["settings.title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["System"].isSelected)
        XCTAssertTrue(app.buttons["Device"].isSelected)
        XCTAssertTrue(app.staticTexts["Notification permission"].exists)
        // The app never asks before an alert is set (TT-142), so a fresh install reads Not asked yet.
        let permission = app.descendants(matching: .any)["settings.permission"]
        XCTAssertTrue(permission.waitForExistence(timeout: 5))
        XCTAssertEqual(permission.label, "Not asked yet")

        app.buttons["Dark"].tap()
        XCTAssertTrue(app.buttons["Dark"].isSelected)
        XCTAssertFalse(app.buttons["System"].isSelected)
        app.buttons["24-hour"].tap()
        XCTAssertTrue(app.buttons["24-hour"].isSelected)

        // Leave the simulator on the defaults for the next run.
        app.buttons["System"].tap()
        app.buttons["Device"].tap()
        XCTAssertTrue(app.buttons["System"].isSelected)
    }

    /// Settings › Testing › Demo trains (D49), in Debug and TestFlight builds: Offline shows the cached timetable with the
    /// Offline status row on Schedule, and the control reads Offline. Launched with the stored choice as an argument, so
    /// nothing is left on the simulator for the next run.
    @MainActor
    func testDemoTrainsOfflineShowsTheOfflineRow() {
        let app = XCUIApplication.onFixtures()
        app.launchArguments += LaunchArguments.fixtureRoute + ["-settings.demoTrains", "offline"]
        app.launch()

        XCTAssertTrue(app.buttons["schedule.route"].waitForExistence(timeout: 10))
        let offline = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Offline · last updated")).firstMatch
        XCTAssertTrue(offline.waitForExistence(timeout: 10))

        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["Demo trains"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Offline"].isSelected)
        XCTAssertFalse(app.buttons["Off"].firstMatch.isSelected)
    }

    /// Settings › Testing › Mock time (TT-158, D51), in Debug and TestFlight builds: Mock time with a quick choice moves
    /// Schedule's clock (the 7:32 AM train is no longer "in 11 min"), and Use real time brings it back.
    @MainActor
    func testMockTimeMovesTheScheduleClockAndUseRealTimeBringsItBack() {
        let app = XCUIApplication.onFixtures()
        app.launchArguments += LaunchArguments.fixtureRoute
        app.launch()

        let card = app.descendants(matching: .any).matching(identifier: "schedule.card.LW-0732-20261105").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        XCTAssertTrue(card.label.contains("in 11 min"), "The fixture clock is 7:21 AM")

        app.tabBars.buttons["Settings"].tap()
        app.buttons["Mock time"].tap()
        let dayChange = app.buttons["settings.mockTime.dayChange"]
        XCTAssertTrue(dayChange.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["settings.mockTime.picker"].exists)
        dayChange.tap()
        XCTAssertTrue(app.buttons["Mock time"].isSelected)

        app.tabBars.buttons["Schedule"].tap()
        wait(for: [expectation(for: NSPredicate(format: "NOT (label CONTAINS 'in 11 min')"), evaluatedWith: card)], timeout: 10)

        app.tabBars.buttons["Settings"].tap()
        app.buttons["settings.mockTime.real"].tap()
        XCTAssertTrue(app.buttons["Real time"].isSelected)
        XCTAssertFalse(app.buttons["settings.mockTime.dayChange"].exists)

        app.tabBars.buttons["Schedule"].tap()
        wait(for: [expectation(for: NSPredicate(format: "label CONTAINS 'in 11 min'"), evaluatedWith: card)], timeout: 10)
    }
}
