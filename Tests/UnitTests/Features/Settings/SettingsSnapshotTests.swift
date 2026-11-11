import SnapshotTesting
import SwiftUI
import XCTest
@testable import TrainTimes

/// Settings after the redesign (TT-168, D57) against design/frames/settings*.png, light and dark: the main view, the three
/// Notifications states, About and Testing. Drawn in the key window so the safe areas render as on the simulator; the tab
/// bar is in the app shell snapshots. Glass is drawn as its solid fallback and the springs are not played (`\.rendersGlass`
/// and `\.playsSettingsMotion` off), so every image is the settled page, and a dark glass control cannot differ between runs.
final class SettingsSnapshotTests: XCTestCase {
    // MARK: Main view

    /// settings.png: notifications on, Testing off (a TestFlight build).
    @MainActor func testMainLight() { snapMain(.allowed, .light, showsTesting: true) }
    /// settings-dark.png: notifications off, Delays and Mock time on.
    @MainActor func testMainDark() { snapMain(.off, .dark, showsTesting: true, testingOn: true) }
    /// settings-store.png: the App Store build, four rows, never asked.
    @MainActor func testMainStoreLight() { snapMain(.notAsked, .light) }
    @MainActor func testMainStoreDark() { snapMain(.notAsked, .dark) }

    // MARK: Notifications

    @MainActor func testNotificationsOnLight() async { snapNotifications(.allowed, .light, await twoAlerts()) }
    @MainActor func testNotificationsOnDark() async { snapNotifications(.allowed, .dark, await twoAlerts()) }
    @MainActor func testNotificationsOffLight() async { snapNotifications(.off, .light, await twoAlerts()) }
    @MainActor func testNotificationsOffDark() async { snapNotifications(.off, .dark, await twoAlerts()) }
    @MainActor func testNotificationsNotAskedLight() async { snapNotifications(.notAsked, .light, await twoAlerts()) }
    @MainActor func testNotificationsNotAskedDark() async { snapNotifications(.notAsked, .dark, await twoAlerts()) }
    /// "Detect my train" on (TT-176).
    @MainActor func testNotificationsDetectOnLight() async {
        snapNotifications(.allowed, .light, await twoAlerts(), detection: BackgroundRig.on())
    }
    /// Turned off by three Not me in a week: the line under the switch.
    @MainActor func testNotificationsDetectTurnedOffDark() async {
        snapNotifications(.allowed, .dark, await twoAlerts(), detection: turnedOff())
    }

    // MARK: About and Testing

    @MainActor func testAboutLight() { snap(SettingsAboutPage(viewModel: model(.allowed)), .light) }
    @MainActor func testAboutDark() { snap(SettingsAboutPage(viewModel: model(.allowed)), .dark) }
    /// settings-testing.png without Mock time: everything off.
    @MainActor func testTestingOffLight() { snap(SettingsTestingPage(viewModel: model(.allowed, showsTesting: true)), .light) }
    @MainActor func testTestingOffDark() { snap(SettingsTestingPage(viewModel: model(.allowed, showsTesting: true)), .dark) }
    /// settings-testing.png: Delays and Mock time at 11:58 PM on Thu Nov 5 (TT-158, D51).
    @MainActor func testTestingMockTimeLight() { snap(SettingsTestingPage(viewModel: model(.allowed, showsTesting: true, testingOn: true)), .light, waits: true) }
    @MainActor func testTestingMockTimeDark() { snap(SettingsTestingPage(viewModel: model(.allowed, showsTesting: true, testingOn: true)), .dark, waits: true) }

    // MARK: Helpers

    @MainActor
    private func model(
        _ permission: NotificationPermission, showsTesting: Bool = false, testingOn: Bool = false, alerts: AlertRules? = nil,
        detection: BackgroundRig? = nil
    ) -> SettingsViewModel {
        let settings = AppSettings(defaults: .ephemeral())
        if testingOn {
            settings.demoTrains = .delays
            settings.mockTime = MockTimeSetting(
                start: Date(timeIntervalSince1970: 1_793_941_080), setAt: Date(timeIntervalSince1970: 1_000_000_000)
            )
        }
        let model = SettingsViewModel(
            settings: settings, permissions: FakeNotificationPermission(permission), appInfo: AppInfo(version: "1.0", build: "12"),
            showsTesting: showsTesting, alerts: alerts, detection: detection?.detection
        )
        model.permission = permission
        return model
    }

    /// The Alerts tab's two rules, so the page says "My alerts 2" as the frames do.
    @MainActor
    private func twoAlerts() async -> AlertRules {
        await AlertsFixtures.rules(FakeAlertServer(), on: [AlertsFixtures.morning, AlertsFixtures.evening])
    }

    @MainActor
    private func snapMain(
        _ permission: NotificationPermission, _ style: UIUserInterfaceStyle, showsTesting: Bool = false, testingOn: Bool = false,
        testName: String = #function, line: UInt = #line
    ) {
        let view = SettingsView(viewModel: model(permission, showsTesting: showsTesting, testingOn: testingOn))
        snap(view, style, testName: testName, line: line)
    }

    /// The switch off after three Not me in a week.
    @MainActor
    private func turnedOff() -> BackgroundRig {
        let defaults = UserDefaults.ephemeral()
        defaults.set(true, forKey: DetectionStore.turnedOffKey)
        return BackgroundRig(defaults: defaults)
    }

    @MainActor
    private func snapNotifications(
        _ permission: NotificationPermission, _ style: UIUserInterfaceStyle, _ alerts: AlertRules, detection: BackgroundRig? = nil,
        testName: String = #function, line: UInt = #line
    ) {
        let page = SettingsNotificationsPage(viewModel: model(permission, alerts: alerts, detection: detection), onShowAlerts: {})
        snap(page, style, testName: testName, line: line)
    }

    @MainActor
    private func snap(
        _ view: some View, _ style: UIUserInterfaceStyle, waits: Bool = false, testName: String = #function, line: UInt = #line
    ) {
        let content = AnyView(view.environment(\.rendersGlass, false).environment(\.playsSettingsMotion, false))
        let image = Snapshotting<AnyView, UIImage>.image(
            drawHierarchyInKeyWindow: true,
            // The compact date picker and the system switch lay out a moment after they appear and anti-alias slightly
            // differently from run to run, so the Mock time page waits a moment and tolerates 1 % of pixels (TT-159).
            precision: waits ? 0.99 : 1,
            perceptualPrecision: 0.98,
            layout: .device(config: .iPhone17Pro),
            traits: UITraitCollection(userInterfaceStyle: style)
        ).comparedAsRecorded
        let strategy: Snapshotting<AnyView, UIImage> = waits ? .wait(for: 0.5, on: image) : image
        assertSnapshot(of: content, as: strategy, testName: testName, line: line)
    }
}
