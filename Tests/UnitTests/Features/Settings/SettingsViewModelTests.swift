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
