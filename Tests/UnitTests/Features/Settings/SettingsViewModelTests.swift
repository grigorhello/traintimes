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
        model.demoTrains = .awaitingPlatform
        XCTAssertEqual(settings.demoTrains, .awaitingPlatform)
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

        model.isMockTimeOn = false
        XCTAssertFalse(model.isMockTimeOn)
        XCTAssertNil(settings.mockTime)
    }

    /// TT-168: the Notifications row is a dot and a word, green On, red Off, grey Off (never asked); empty until read.
    func testNotificationRowShowsADotAndAWordPerPermission() async {
        let model = makeModel(.allowed)
        XCTAssertNil(model.notificationDot, "Nothing to show before the first read")
        XCTAssertNil(model.notificationWord)

        for (permission, dot, word) in [
            (NotificationPermission.allowed, SettingsViewModel.NotificationDot.green, "On"),
            (.off, .red, "Off"),
            (.notAsked, .grey, "Off"),
        ] {
            let model = makeModel(permission)
            await model.refreshPermission()
            XCTAssertEqual(model.notificationDot, dot)
            XCTAssertEqual(model.notificationWord, word)
        }
    }

    /// TT-168: the Testing row reads Off, or what is on, and Reset turns everything off.
    func testTestingValueNamesWhatIsOnAndResetTurnsItOff() {
        let settings = AppSettings(defaults: .ephemeral())
        let model = makeModel(settings: settings, showsTesting: true)
        XCTAssertFalse(model.isTestingActive)
        XCTAssertEqual(model.testingValue, "Off")

        model.demoTrains = .delays
        XCTAssertTrue(model.isTestingActive)
        XCTAssertEqual(model.testingValue, "Delays")
        model.demoTrains = .awaitingPlatform
        XCTAssertEqual(model.testingValue, "Platform")
        model.isMockTimeOn = true
        XCTAssertEqual(model.testingValue, "Platform · Mock time")
        model.demoTrains = .off
        XCTAssertEqual(model.testingValue, "Mock time")
        XCTAssertTrue(model.isTestingActive, "Mock time alone is something on")

        model.demoTrains = .offline
        model.resetTesting()
        XCTAssertEqual(settings.demoTrains, .off)
        XCTAssertNil(settings.mockTime)
        XCTAssertFalse(model.isTestingActive)
        XCTAssertEqual(model.testingValue, "Off")
    }

    /// TT-168: "My alerts · N" counts every saved rule; none without alert rules.
    func testAlertCountIsTheNumberOfSavedRules() async {
        XCTAssertEqual(makeModel().alertCount, 0)
        let rules = await AlertsFixtures.rules(FakeAlertServer(), on: [AlertsFixtures.morning, AlertsFixtures.evening])
        let model = SettingsViewModel(
            settings: AppSettings(defaults: .ephemeral()), permissions: FakeNotificationPermission(.allowed),
            appInfo: AppInfo(version: "1.0", build: "1"), showsTesting: false, alerts: rules
        )
        XCTAssertEqual(model.alertCount, 2)
    }

    /// TT-168: "Turn on notifications" shows the iOS prompt once and the row and page follow the answer.
    func testTurnOnNotificationsAsksOnceAndReadsTheAnswer() async {
        let prompt = PromptingPermission(answer: .allowed)
        let model = SettingsViewModel(
            settings: AppSettings(defaults: .ephemeral()), permissions: prompt, appInfo: AppInfo(version: "1.0", build: "1"),
            showsTesting: false
        )
        await model.refreshPermission()
        XCTAssertEqual(model.permission, .notAsked)

        await model.turnOnNotifications()
        XCTAssertEqual(model.permission, .allowed)
        XCTAssertEqual(model.notificationDot, .green)
        let asked = await prompt.asked
        XCTAssertEqual(asked, 1)
    }

    /// The same prompt through the alert rules, which is what the app wires (D41, revised by D57).
    func testTurnOnNotificationsGoesThroughTheAlertRules() async {
        let prompt = PromptingPermission(answer: .off)
        let rules = AlertRules(server: FakeAlertServer(), push: FixturePushRegistration(), permissions: prompt, defaults: nil)
        let model = SettingsViewModel(
            settings: AppSettings(defaults: .ephemeral()), permissions: prompt, appInfo: AppInfo(version: "1.0", build: "1"),
            showsTesting: false, alerts: rules
        )
        await model.turnOnNotifications()
        XCTAssertEqual(model.permission, .off, "A denied prompt reads Off, red")
        XCTAssertEqual(model.notificationDot, .red)
        let asked = await prompt.asked
        XCTAssertEqual(asked, 1)
    }

    func testVersionIsShownAsValueAndAsPill() {
        XCTAssertEqual(makeModel().versionValue, "1.0 (1)")
        XCTAssertEqual(makeModel().versionLine, "Version 1.0 (1)")
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

/// A permission that has not been asked until `request()`, which answers `answer` and counts the asks.
private actor PromptingPermission: NotificationPermissionProviding {
    private var value = NotificationPermission.notAsked
    private let answer: NotificationPermission
    private(set) var asked = 0

    init(answer: NotificationPermission) {
        self.answer = answer
    }

    func current() async -> NotificationPermission { value }

    func request() async -> NotificationPermission {
        asked += 1
        value = answer
        return value
    }
}
