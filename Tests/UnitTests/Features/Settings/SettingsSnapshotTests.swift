import SnapshotTesting
import SwiftUI
import XCTest
@testable import TrainTimes

/// The Settings tab (D48) against the canvas "Settings" frame, one per notification permission state, light and dark.
/// Drawn in the key window so the safe areas render as on the simulator; the tab bar is in the app shell snapshots.
final class SettingsSnapshotTests: XCTestCase {
    @MainActor func testAllowedLight() { snap(.allowed, .light) }
    @MainActor func testAllowedDark() { snap(.allowed, .dark) }
    @MainActor func testOffLight() { snap(.off, .light) }
    @MainActor func testOffDark() { snap(.off, .dark) }
    @MainActor func testNotAskedLight() { snap(.notAsked, .light) }
    @MainActor func testNotAskedDark() { snap(.notAsked, .dark) }
    /// The Testing section of TestFlight and Debug builds, with Delays chosen (D49).
    @MainActor func testTestingSectionLight() { snap(.allowed, .light, showsTesting: true) }
    @MainActor func testTestingSectionDark() { snap(.allowed, .dark, showsTesting: true) }

    @MainActor
    private func snap(
        _ permission: NotificationPermission, _ style: UIUserInterfaceStyle, showsTesting: Bool = false,
        testName: String = #function, line: UInt = #line
    ) {
        let settings = AppSettings(defaults: .ephemeral())
        if showsTesting { settings.demoTrains = .delays }
        let model = SettingsViewModel(
            settings: settings, permissions: FakeNotificationPermission(permission), appInfo: AppInfo(version: "1.0", build: "1"),
            showsTesting: showsTesting
        )
        model.permission = permission
        assertSnapshot(
            of: SettingsView(viewModel: model),
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
