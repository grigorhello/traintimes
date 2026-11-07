import Observation
import SwiftUI
import XCTest
@testable import TrainTimes

@MainActor
final class AppSettingsTests: XCTestCase {
    /// 5:05 PM in Toronto on 2026-11-05 (EST).
    private var evening: Date { ISO8601DateFormatter().date(from: "2026-11-05T22:05:00Z")! }

    func testDefaultsAreSystemAndDevice() {
        let settings = AppSettings(defaults: .ephemeral())
        XCTAssertEqual(settings.appearance, .system)
        XCTAssertEqual(settings.timeFormat, .device)
    }

    func testChoicesAreStoredOnDevice() {
        let defaults = UserDefaults.ephemeral()
        let settings = AppSettings(defaults: defaults)
        settings.appearance = .dark
        settings.timeFormat = .twentyFourHour

        let reopened = AppSettings(defaults: defaults)
        XCTAssertEqual(reopened.appearance, .dark)
        XCTAssertEqual(reopened.timeFormat, .twentyFourHour)
    }

    func testUnknownStoredValuesFallBackToDefaults() {
        let defaults = UserDefaults.ephemeral()
        defaults.set("sepia", forKey: AppSettings.appearanceKey)
        defaults.set("36-hour", forKey: AppSettings.timeFormatKey)
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.appearance, .system)
        XCTAssertEqual(settings.timeFormat, .device)
    }

    func testFormatterFollowsTimeFormat() {
        let settings = AppSettings(defaults: .ephemeral())
        settings.timeFormat = .twelveHour
        XCTAssertEqual(settings.timeFormatter.time(evening), "5:05 PM")
        settings.timeFormat = .twentyFourHour
        XCTAssertEqual(settings.timeFormatter.time(evening), "17:05")
    }

    /// Anything that formatted a time through `timeFormatter` is invalidated the moment Time format changes,
    /// so every time on screen re-renders at once.
    func testTimeFormatChangeInvalidatesFormattedTimes() async {
        let settings = AppSettings(defaults: .ephemeral())
        let changed = expectation(description: "formatter observers notified")
        withObservationTracking {
            _ = settings.timeFormatter.time(evening)
        } onChange: {
            changed.fulfill()
        }
        settings.timeFormat = .twentyFourHour
        await fulfillment(of: [changed], timeout: 1)
    }

    func testAppearanceMapsToColorScheme() {
        XCTAssertNil(Appearance.system.colorScheme)
        XCTAssertEqual(Appearance.light.colorScheme, .light)
        XCTAssertEqual(Appearance.dark.colorScheme, .dark)
    }
}
