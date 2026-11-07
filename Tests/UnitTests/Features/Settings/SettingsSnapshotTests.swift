import SnapshotTesting
import SwiftUI
import XCTest
@testable import TrainTimes

/// Settings against design/frames/settings.png, one per notification permission state, light and dark.
/// Pushed on the Schedule stack, as from the gear, so the navigation bar and back button render as on the simulator.
/// No TabView: Settings hides the tab bar, and inside a TabView the hide animation races the capture.
final class SettingsSnapshotTests: XCTestCase {
    @MainActor func testAllowedLight() { snap(.allowed, .light) }
    @MainActor func testAllowedDark() { snap(.allowed, .dark) }
    @MainActor func testOffLight() { snap(.off, .light) }
    @MainActor func testOffDark() { snap(.off, .dark) }
    @MainActor func testNotAskedLight() { snap(.notAsked, .light) }
    @MainActor func testNotAskedDark() { snap(.notAsked, .dark) }

    @MainActor
    private func snap(
        _ permission: NotificationPermission, _ style: UIUserInterfaceStyle, testName: String = #function, line: UInt = #line
    ) {
        let settings = AppSettings(defaults: .ephemeral())
        let model = SettingsViewModel(
            settings: settings, permissions: FakeNotificationPermission(permission), appInfo: AppInfo(version: "1.0", build: "1")
        )
        model.permission = permission
        // The root carries Schedule's title, so the back button reads "Train Times" as in the app.
        let pushed = NavigationStack(path: .constant([ScheduleRoute.settings])) {
            TTColor.canvas
                .navigationTitle(Text("app.name"))
                .navigationDestination(for: ScheduleRoute.self) { _ in SettingsView(viewModel: model) }
        }

        assertSnapshot(
            of: pushed,
            as: .image(
                drawHierarchyInKeyWindow: true,
                perceptualPrecision: 0.98,
                layout: .device(config: .iPhone17Pro),
                traits: UITraitCollection(userInterfaceStyle: style)
            ),
            testName: testName,
            line: line
        )
    }
}
