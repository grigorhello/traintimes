import XCTest

final class LaunchTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testAppLaunchesToRootView() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["root.title"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["root.title"].label, "Train Times")
    }
}
