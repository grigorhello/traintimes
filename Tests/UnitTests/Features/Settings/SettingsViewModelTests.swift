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
            showsTesting: showsTesting,
            defaults: .ephemeral()
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
        XCTAssertEqual(model.timeFormat, .device)

        model.timeFormat = .twelveHour
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

    /// TT-195: Live data and the Demo trains modes that make their own live status are one at a time; the row names it and
    /// Reset turns it off. Ride and Departure keep Live data on.
    func testLiveDataAndDemoTrainsAreOneAtATime() {
        let settings = AppSettings(defaults: .ephemeral())
        let model = makeModel(settings: settings, showsTesting: true)
        model.demoTrains = .delays
        model.mockLive = .mixed
        XCTAssertEqual(settings.demoTrains, .off)
        XCTAssertEqual(model.testingValue, "Live: Mixed")
        XCTAssertTrue(model.isTestingActive)

        model.demoTrains = .ride
        XCTAssertEqual(settings.mockLive, .mixed)
        model.demoTrains = .offline
        XCTAssertEqual(settings.mockLive, .off)

        model.mockLive = .stale
        model.resetTesting()
        XCTAssertEqual(settings.mockLive, .off)
        XCTAssertFalse(model.isTestingActive)
    }

    /// TT-233, D114: Live data › Board is the sixth choice. Its raw value is the launch argument (`-settings.mockLive
    /// boarding`) and the end of the switch's identifier; the Testing row names it, it is one at a time with Delays, and
    /// Reset turns it off.
    func testLiveDataBoardIsNamedOnTheRowAndResetTurnsItOff() {
        XCTAssertEqual(MockLive.allCases, [.off, .onTime, .mixed, .changing, .stale, .boarding])
        XCTAssertEqual(MockLive.boarding.rawValue, "boarding")
        XCTAssertEqual(MockLive.boarding.labelKey, "settings.live_data.boarding")

        let defaults = UserDefaults.ephemeral()
        let settings = AppSettings(defaults: defaults)
        let model = makeModel(settings: settings, showsTesting: true)
        model.demoTrains = .delays
        model.mockLive = .boarding
        XCTAssertEqual(settings.mockLive, .boarding)
        XCTAssertEqual(settings.demoTrains, .off, "Delays makes its own live status")
        XCTAssertEqual(defaults.string(forKey: MockLive.key), "boarding")
        XCTAssertEqual(AppSettings(defaults: defaults).mockLive, .boarding, "read back at the next launch")
        XCTAssertTrue(model.isTestingActive)
        XCTAssertEqual(model.testingValue, "Live: Board")

        model.demoTrains = .departure
        XCTAssertEqual(settings.mockLive, .boarding, "Depart leaves live status alone")
        XCTAssertEqual(model.testingValue, "Depart · Live: Board")

        model.resetTesting()
        XCTAssertEqual(settings.mockLive, .off)
        XCTAssertEqual(settings.demoTrains, .off)
        XCTAssertFalse(model.isTestingActive)
        XCTAssertEqual(model.testingValue, "Off")
    }

    /// TT-242, D120: Automatic ride shows under Depart only. Its raw values are the launch argument (`-settings.demoAutoRide
    /// noFeed`) and the end of the switch's identifiers; the choice is stored, the Testing row names it, and Reset turns it
    /// off.
    func testAutomaticRideShowsWithDepartAndResetTurnsItOff() {
        XCTAssertEqual(DemoAutoRide.allCases, [.off, .boards, .stays, .noFeed])
        XCTAssertEqual(DemoAutoRide.allCases.map(\.rawValue), ["off", "boards", "stays", "noFeed"])

        let defaults = UserDefaults.ephemeral()
        let settings = AppSettings(defaults: defaults)
        let model = makeModel(settings: settings, showsTesting: true)
        XCTAssertEqual(model.demoAutoRide, .off)
        XCTAssertFalse(model.showsDemoAutoRide)
        model.demoTrains = .ride
        XCTAssertFalse(model.showsDemoAutoRide, "Ride has Express but no Automatic ride")
        model.demoTrains = .departure
        XCTAssertTrue(model.showsDemoAutoRide)
        XCTAssertEqual(model.testingValue, "Depart")

        model.demoAutoRide = .boards
        XCTAssertEqual(settings.demoAutoRide, .boards)
        XCTAssertEqual(defaults.string(forKey: DemoAutoRide.key), "boards")
        XCTAssertEqual(AppSettings(defaults: defaults).demoAutoRide, .boards, "read back at the next launch")
        XCTAssertTrue(model.isTestingActive)
        XCTAssertEqual(model.testingValue, "Depart · Automatic ride")
        model.isMockTimeOn = true
        XCTAssertEqual(model.testingValue, "Depart · Automatic ride · Mock time")

        model.resetTesting()
        XCTAssertEqual(settings.demoAutoRide, .off)
        XCTAssertEqual(settings.demoTrains, .off)
        XCTAssertFalse(model.showsDemoAutoRide)
        XCTAssertFalse(model.isTestingActive)
        XCTAssertEqual(model.testingValue, "Off")
    }

    /// TT-242, D120: Last check in words: each outcome, the seconds after the train left (0 without them), the reason when
    /// it could not tell, and the hold on a second line in the Time format the view passes.
    func testLastCheckInWords() {
        let twelve = TimeFormatter(format: .twelveHour)
        func text(
            _ outcome: AutoRideCheck.Outcome, _ reason: AutoRideCheck.Reason? = nil, seconds: Int? = nil, hold: Date? = nil,
            formatter: TimeFormatter = TimeFormatter(format: .twelveHour)
        ) -> String {
            let check = AutoRideCheck(outcome: outcome, reason: reason, secondsAfter: seconds, holdReachedAt: hold)
            return SettingsViewModel.lastCheckText(check, formatter: formatter)
        }

        XCTAssertEqual(SettingsViewModel.lastCheckText(nil, formatter: twelve), "None yet")
        XCTAssertEqual(text(.started, seconds: 104), "Started 104 s after it left")
        XCTAssertEqual(text(.started), "Started 0 s after it left", "no seconds read as 0")
        XCTAssertEqual(text(.notOnBoard, seconds: 75), "Not on board after 75 s")
        XCTAssertEqual(text(.unsure, .noFeed, seconds: 180), "Can’t tell after 180 s: no train position")
        XCTAssertEqual(text(.answered, seconds: 40), "Answered first")
        XCTAssertEqual(text(.stopped), "Stopped")
        XCTAssertEqual(text(.notArmed), "Not armed")

        // 5:14 PM in Toronto on Thu Nov 5 2026 (EST).
        let hold = Date(timeIntervalSince1970: 1_793_916_840)
        XCTAssertEqual(text(.started, seconds: 104, hold: hold), "Started 104 s after it left\nHold sent at 5:14 PM")
        XCTAssertEqual(
            text(.unsure, .rival, seconds: 180, hold: hold, formatter: TimeFormatter(format: .twentyFourHour)),
            "Can’t tell after 180 s: another train beside it\nHold sent at 17:14"
        )
        XCTAssertEqual(text(.stopped, hold: hold), "Stopped\nHold sent at 5:14 PM")
    }

    /// Every reason the rule gives has its words in the strings file.
    func testEveryLastCheckReasonHasWords() {
        let reasons: [(AutoRideCheck.Reason, String)] = [
            (.noFeed, "no train position"),
            (.noStation, "never at the station"),
            (.rival, "another train beside it"),
            (.weakFixes, "weak location"),
            (.short, "too close to your stop"),
        ]
        for (reason, words) in reasons {
            let check = AutoRideCheck(outcome: .unsure, reason: reason, secondsAfter: 12, holdReachedAt: nil)
            let text = SettingsViewModel.lastCheckText(check, formatter: TimeFormatter(format: .twelveHour))
            XCTAssertEqual(text, "Can’t tell after 12 s: \(words)", reason.rawValue)
            XCTAssertFalse(text.contains("settings.last_check"), "\(reason.rawValue) has no string")
        }
    }

    /// The page reads the check through the closure RootView passes; none before any.
    func testLastCheckReadsTheWatchsCheck() {
        let formatter = TimeFormatter(format: .twelveHour)
        XCTAssertEqual(makeModel(showsTesting: true).lastCheckText(formatter: formatter), "None yet")

        let check = AutoRideCheck(outcome: .notOnBoard, reason: nil, secondsAfter: 62, holdReachedAt: nil)
        let model = SettingsViewModel(
            settings: AppSettings(defaults: .ephemeral()), permissions: FakeNotificationPermission(.allowed),
            appInfo: AppInfo(version: "1.0", build: "1"), showsTesting: true, autoRideCheck: { check }, defaults: .ephemeral()
        )
        XCTAssertEqual(model.lastCheckText(formatter: formatter), "Not on board after 62 s")
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

    /// TT-169: the off card speaks of the alerts that are switched on, not of every saved rule.
    func testSwitchedOnCountLeavesOutPausedAlerts() async {
        XCTAssertEqual(makeModel().switchedOnCount, 0)
        let rules = await AlertsFixtures.rules(FakeAlertServer(), on: [AlertsFixtures.morning, AlertsFixtures.evening])
        let model = SettingsViewModel(
            settings: AppSettings(defaults: .ephemeral()), permissions: FakeNotificationPermission(.off),
            appInfo: AppInfo(version: "1.0", build: "1"), showsTesting: false, clock: FixedClock(now: AlertsFixtures.now), alerts: rules
        )
        XCTAssertEqual(model.alertCount, 2)
        XCTAssertEqual(model.switchedOnCount, 1, "the evening alert is paused")
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
