import SnapshotTesting
import SwiftUI
import XCTest
@testable import TrainTimes

/// Settings after the redesign (TT-168, D57) against design/frames/settings*.png, light and dark: the main view with the
/// Automatic direction card in each of its states (TT-234, D116), the three Notifications states, About and Testing. Drawn
/// in the key window so the safe areas render as on the simulator; the tab bar is in the app shell snapshots. Glass is
/// drawn as its solid fallback and the springs are not played (`\.rendersGlass` and `\.playsSettingsMotion` off), so every
/// image is the settled page, and a dark glass control cannot differ between runs.
final class SettingsSnapshotTests: XCTestCase {
    // MARK: Main view

    /// settings.png with the Automatic direction card on (board 17): notifications on, Testing off (a TestFlight build).
    @MainActor func testMainLight() { snapMain(.allowed, .light, showsTesting: true, direction: FakeDirectionLocation()) }
    /// settings-dark.png: notifications off, Delays and Mock time on, Automatic direction on.
    @MainActor func testMainDark() {
        snapMain(.off, .dark, showsTesting: true, testingOn: true, direction: FakeDirectionLocation())
    }
    /// settings-store.png: the App Store build, six rows, nothing asked yet: Automatic direction off with its plain note.
    @MainActor func testMainStoreLight() { snapMain(.notAsked, .light, direction: FakeDirectionLocation(permission: .notAsked)) }
    @MainActor func testMainStoreDark() { snapMain(.notAsked, .dark, direction: FakeDirectionLocation(permission: .notAsked)) }
    /// Location refused: Automatic direction off, "Needs your location. Allow it in iOS Settings."
    @MainActor func testMainNeedsLocationLight() {
        snapMain(.allowed, .light, direction: FakeDirectionLocation(permission: .refused))
    }
    @MainActor func testMainNeedsLocationDark() {
        snapMain(.allowed, .dark, direction: FakeDirectionLocation(permission: .refused))
    }
    /// Precise Location off: Automatic direction off, "Needs Precise Location. Turn it on in iOS Settings."
    @MainActor func testMainNeedsPreciseLight() { snapMain(.allowed, .light, direction: FakeDirectionLocation(isPrecise: false)) }
    @MainActor func testMainNeedsPreciseDark() { snapMain(.allowed, .dark, direction: FakeDirectionLocation(isPrecise: false)) }

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
    /// Turned off by three "No" in a week: the line under the switch.
    @MainActor func testNotificationsDetectTurnedOffDark() async {
        snapNotifications(.allowed, .dark, await twoAlerts(), detection: turnedOff())
    }

    // MARK: About and Testing

    @MainActor func testAboutLight() { snap(SettingsAboutPage(viewModel: model(.allowed)), .light) }
    @MainActor func testAboutDark() { snap(SettingsAboutPage(viewModel: model(.allowed)), .dark) }
    /// settings-testing.png without Mock time: everything off, Demo place with the route's two stations and no look yet
    /// (TT-234, D116).
    @MainActor func testTestingOffLight() { snap(SettingsTestingPage(viewModel: testingModel()), .light) }
    @MainActor func testTestingOffDark() { snap(SettingsTestingPage(viewModel: testingModel()), .dark) }
    /// settings-testing.png: Delays and Mock time at 11:58 PM on Thu Nov 5 (TT-158, D51).
    @MainActor func testTestingMockTimeLight() {
        snap(SettingsTestingPage(viewModel: testingModel(testingOn: true)), .light, waits: true)
    }
    @MainActor func testTestingMockTimeDark() {
        snap(SettingsTestingPage(viewModel: testingModel(testingOn: true)), .dark, waits: true)
    }
    /// TT-195: Live data on Mixed (Demo trains off, as choosing it turns Delays off).
    @MainActor func testTestingLiveDataLight() { snap(SettingsTestingPage(viewModel: liveModel()), .light) }
    @MainActor func testTestingLiveDataDark() { snap(SettingsTestingPage(viewModel: liveModel()), .dark) }
    /// TT-234, D116: Demo place at Union, the route's To station.
    @MainActor func testTestingDemoPlaceLight() { snap(SettingsTestingPage(viewModel: demoPlaceModel()), .light) }
    @MainActor func testTestingDemoPlaceDark() { snap(SettingsTestingPage(viewModel: demoPlaceModel()), .dark) }
    /// TT-242, D120: Depart with Automatic ride on Boards, and Last check under the card: the ride started 104 s after the
    /// train left, the hold reached the server at 5:14 PM.
    @MainActor func testTestingDemoAutoRideLight() { snap(autoRidePage(), .light) }
    @MainActor func testTestingDemoAutoRideDark() { snap(autoRidePage(), .dark) }

    // MARK: Haptics (TT-214)

    @MainActor func testHapticsLight() { snap(SettingsHapticsPage(), .light) }
    @MainActor func testHapticsDark() { snap(SettingsHapticsPage(), .dark) }

    // MARK: Helpers

    /// The Testing page's model on the fixture route, Oakville to Union, so Demo place shows its two stations.
    @MainActor
    private func testingModel(testingOn: Bool = false) -> SettingsViewModel {
        model(.allowed, showsTesting: true, testingOn: testingOn, route: AlertFixtures.route)
    }

    @MainActor
    private func liveModel() -> SettingsViewModel {
        let page = testingModel()
        page.mockLive = .mixed
        return page
    }

    @MainActor
    private func demoPlaceModel() -> SettingsViewModel {
        let page = testingModel()
        page.demoPlace = AlertFixtures.route.to.id
        return page
    }

    /// The Testing page with Depart and Automatic ride on Boards, its times in the 12-hour format so the hold reads 5:14 PM
    /// on any simulator.
    @MainActor
    private func autoRidePage() -> some View {
        let check = AutoRideCheck(
            outcome: .started, reason: nil, secondsAfter: 104, holdReachedAt: Date(timeIntervalSince1970: 1_793_916_840)
        )
        let page = model(.allowed, showsTesting: true, route: AlertFixtures.route, autoRideCheck: check)
        page.demoTrains = .departure
        page.demoAutoRide = .boards
        return SettingsTestingPage(viewModel: page).environment(\.timeFormatter, TimeFormatter(format: .twelveHour))
    }

    /// `direction` is Automatic direction's location reader, with nothing stored; nil is no reader, which reads off.
    /// Demo place is kept in defaults of its own, never the app's. `autoRideCheck` is what Last check shows.
    @MainActor
    private func model(
        _ permission: NotificationPermission, showsTesting: Bool = false, testingOn: Bool = false, alerts: AlertRules? = nil,
        detection: BackgroundRig? = nil, direction: (any DirectionLocating)? = nil, route: Route? = nil,
        autoRideCheck: AutoRideCheck? = nil
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
            showsTesting: showsTesting, alerts: alerts, detection: detection?.detection, direction: direction,
            directionStore: DirectionStore(defaults: nil), route: { route }, autoRideCheck: { autoRideCheck },
            defaults: .ephemeral()
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
        direction: (any DirectionLocating)? = nil, testName: String = #function, line: UInt = #line
    ) {
        let view = SettingsView(
            viewModel: model(permission, showsTesting: showsTesting, testingOn: testingOn, direction: direction)
        )
        snap(view, style, testName: testName, line: line)
    }

    /// The switch off after three "No" in a week.
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
