import XCTest

/// Feedback and questions (TT-202, D85): from Schedule's Feedback pill and from Settings › Support. UI tests run on the
/// fixtures, so Send reaches the fixture sender, never the alert server.
final class FeedbackTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testSendFeedbackFromSchedule() {
        let app = XCUIApplication.onFixtures()
        app.launchArguments += LaunchArguments.fixtureRoute + LaunchArguments.noAlerts
        app.launch()

        let pill = app.buttons["schedule.feedback"]
        XCTAssertTrue(pill.waitForExistence(timeout: 15))
        pill.tap()

        let send = app.buttons["feedback.send"]
        XCTAssertTrue(send.waitForExistence(timeout: 15))
        XCTAssertFalse(send.isEnabled, "Nothing to send yet")
        let message = app.textViews["feedback.message"]
        message.tap()
        message.typeText("The timeline is great")
        XCTAssertTrue(send.isEnabled)
        send.tap()

        let done = app.buttons["feedback.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 15))
        done.tap()
        XCTAssertTrue(pill.waitForExistence(timeout: 15))
    }

    @MainActor
    func testAskAQuestionFromSettings() {
        let app = XCUIApplication.onFixtures()
        app.launchArguments += LaunchArguments.fixtureRoute + LaunchArguments.noAlerts
        app.launch()

        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["settings.emailUs"].waitForExistence(timeout: 15))
        app.buttons["settings.feedback"].tap()

        XCTAssertTrue(app.buttons["feedback.kind.question"].waitForExistence(timeout: 15))
        app.buttons["feedback.kind.question"].tap()
        XCTAssertTrue(app.buttons["feedback.kind.question"].isSelected)
        let message = app.textViews["feedback.message"]
        message.tap()
        message.typeText("Does it work on weekends?")
        let email = app.textFields["feedback.email"]
        email.tap()
        email.typeText("rider@example.com")
        app.buttons["feedback.send"].tap()

        XCTAssertTrue(app.staticTexts["We’ll reply by email."].waitForExistence(timeout: 15))
        app.buttons["feedback.done"].tap()
        XCTAssertTrue(app.buttons["settings.feedback"].waitForExistence(timeout: 15))
    }
}
