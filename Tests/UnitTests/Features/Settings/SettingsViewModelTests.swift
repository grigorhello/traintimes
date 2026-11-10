import UIKit
import UserNotifications
import XCTest
@testable import TrainTimes

@MainActor
final class SettingsViewModelTests: XCTestCase {
    private func makeModel(
        _ permission: NotificationPermission = .allowed, settings: AppSettings? = nil, showsTesting: Bool = false
    ) -> SettingsViewModel {
        SettingsViewModel(
            settings: settings ?? AppSettings(defaults: .ephemeral()),
            permissions: FakeNotificationPermission(permission),
            appInfo: AppInfo(version: "1.0", build: "1"),
            showsTesting: showsTesting
        )
    }

    func testPermissionIsReadFromTheSystem() async {
        for permission in NotificationPermission.allCases {
            let model = makeModel(permission)
            XCTAssertNil(model.permission)
            await model.refreshPermission()
            XCTAssertEqual(model.permission, permission)
        }
    }

    func testAuthorizationStatusInWords() {
        XCTAssertEqual(NotificationPermission(.authorized), .allowed)
        XCTAssertEqual(NotificationPermission(.provisional), .allowed)
        XCTAssertEqual(NotificationPermission(.ephemeral), .allowed)
        XCTAssertEqual(NotificationPermission(.denied), .off)
        XCTAssertEqual(NotificationPermission(.notDetermined), .notAsked)
    }

    func testChoicesWriteThroughToSettings() {
        let settings = AppSettings(defaults: .ephemeral())
        let model = makeModel(settings: settings)
        XCTAssertEqual(model.appearance, .system)
        XCTAssertEqual(model.timeFormat, .device)

        model.appearance = .dark
        model.timeFormat = .twelveHour
        XCTAssertEqual(settings.appearance, .dark)
        XCTAssertEqual(settings.timeFormat, .twelveHour)
    }

    /// Demo trains lives in the Testing section, which only TestFlight and Debug builds show (D49).
    func testDemoTrainsWritesThroughToSettings() {
        let settings = AppSettings(defaults: .ephemeral())
        let model = makeModel(settings: settings, showsTesting: true)
        XCTAssertTrue(model.showsTesting)
        XCTAssertEqual(model.demoTrains, .off)
        model.demoTrains = .offline
        XCTAssertEqual(settings.demoTrains, .offline)
        XCTAssertFalse(makeModel().showsTesting, "The App Store build has no Testing section")
    }

    /// TT-158: Mock time starts from the app's current time, keeps the picker's value, and Use real time clears it.
    func testMockTimeStartsFromTheClockAndPresetsKeepThePickersDate() async throws {
        // 7:21 AM in Toronto on Thu Nov 5 2026 (EST).
        let now = Date(timeIntervalSince1970: 1_793_881_260)
        let settings = AppSettings(defaults: .ephemeral())
        let model = SettingsViewModel(
            settings: settings, permissions: FakeNotificationPermission(.allowed), appInfo: AppInfo(version: "1.0", build: "1"),
            showsTesting: true, clock: FixedClock(now: now)
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = goTimeZone
        XCTAssertFalse(model.isMockTimeOn)
        model.isMockTimeOn = true
        XCTAssertTrue(model.isMockTimeOn)
        XCTAssertEqual(settings.mockTime?.start, now)

        for (preset, time) in [(MockTimePreset.early, "5:00 AM"), (.late, "11:45 PM"), (.dayChange, "11:58 PM")] {
            model.chooseMockTime(preset)
            XCTAssertEqual(TimeFormatter(format: .twelveHour).time(model.mockTimeStart), time)
            XCTAssertEqual(calendar.component(.day, from: model.mockTimeStart), 5, "Still the picker's date")
        }

        // Tapping the preset again is a new choice that starts the clock again, though the minute is the same.
        let first = try XCTUnwrap(settings.mockTime)
        try await Task.sleep(for: .milliseconds(20))
        model.chooseMockTime(.dayChange)
        XCTAssertEqual(settings.mockTime?.start, first.start)
        XCTAssertGreaterThan(try XCTUnwrap(settings.mockTime).setAt, first.setAt)

        // The picker handing back the minute it was given is not a choice.
        let beforeEcho = try XCTUnwrap(settings.mockTime)
        model.mockTimeStart = beforeEcho.start
        XCTAssertEqual(settings.mockTime, beforeEcho)

        model.useRealTime()
        XCTAssertFalse(model.isMockTimeOn)
        XCTAssertNil(settings.mockTime)
    }

    func testVersionLine() {
        XCTAssertEqual(makeModel().versionLine, "Version 1.0 (1) · Your next GO train, at a glance.")
    }

    func testVersionComesFromTheBundle() {
        XCTAssertFalse(AppInfo.main.version.isEmpty)
        XCTAssertEqual(AppInfo.main.build, "1")
    }

    func testLinks() {
        XCTAssertEqual(SettingsViewModel.dataURL.absoluteString, "https://traintimes.ca/data")
        XCTAssertEqual(SettingsViewModel.privacyURL.absoluteString, "https://traintimes.ca/privacy")
        XCTAssertEqual(SettingsViewModel.officialUpdatesURL.host(), "www.gotransit.com")
        XCTAssertEqual(makeModel().notificationSettingsURL.absoluteString, UIApplication.openNotificationSettingsURLString)
    }
}
