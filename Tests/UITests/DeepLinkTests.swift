import XCTest

/// Tapping a notification opens Trip details for its trip and service date, even from a closed app; a past service date
/// opens the Alerts tab (TT-144). The app launches with the alert server's payload as a stand-in for the tap that
/// launched it, on the fixture clock, Thu Nov 5.
final class DeepLinkTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// From a cold start with no saved route, as after the route was changed: the trip opens on the alert's route.
    @MainActor
    func testNotificationOpensTheTripFromAColdStart() {
        let app = XCUIApplication.onFixtures(notification: Self.payload(serviceDate: "20261105"))
        app.launchArguments += LaunchArguments.freshInstall
        app.launch()

        let sheet = app.descendants(matching: .any).matching(identifier: "sheet.tripDetails").firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 10))
        // The line names the sheet; the train's name is the sheet's label; the fixture feed is live, so the status row says so.
        XCTAssertTrue(app.staticTexts["trip.title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["trip.title"].label, "Lakeshore West")
        XCTAssertEqual(sheet.label, "7:58 AM train")
        XCTAssertTrue(app.staticTexts["Updated just now"].exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "trip.stop.UN").firstMatch.waitForExistence(timeout: 5))

        // Closing the sheet shows the next trains on that route.
        app.buttons["trip.close"].tap()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["schedule.from"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "schedule.card.LW-0758-20261105").firstMatch.exists)
    }

    @MainActor
    func testPastServiceDateOpensAlerts() {
        let app = XCUIApplication.onFixtures(notification: Self.payload(serviceDate: "20261104"))
        app.launchArguments += LaunchArguments.fixtureRoute
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "alerts.root").firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["Alerts"].isSelected)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "sheet.tripDetails").firstMatch.exists)
    }

    /// What `server/src/monitor.ts` puts beside `aps` for the 7:58 AM train, Oakville to Union.
    private static func payload(serviceDate: String) -> String {
        #"{"tripId":"LW-0758-20261105","serviceDate":"\#(serviceDate)","originId":"OA","destinationId":"UN"}"#
    }
}

extension XCUIApplication {
    /// The app on the fixtures, launched as if by a tap on a notification with this payload (JSON).
    static func onFixtures(notification payload: String) -> XCUIApplication {
        let app = onFixtures()
        app.launchEnvironment["TT_NOTIFICATION"] = payload
        return app
    }
}
