import SnapshotTesting
import SwiftUI
import XCTest
@testable import TrainTimes

/// The alert setup sheet against design/frames/alert-setup.png, alert-setup-repeat.png and permission-prompt.png, light
/// and dark: a new This-trip and Repeat alert, Setting up, On (Manage alert), Notifications off and Could not save. The
/// sheet is drawn at the bottom of the screen on its own; the system draws the grabber and the dimmed timetable.
final class AlertSetupSnapshotTests: XCTestCase {
    @MainActor func testThisTripLight() { snap(model(), .light) }
    @MainActor func testThisTripDark() { snap(model(), .dark) }
    @MainActor func testRepeatLight() { snap(model(.repeating), .light) }
    @MainActor func testRepeatDark() { snap(model(.repeating), .dark) }
    @MainActor func testSettingUpLight() async { await settingUp(.light) }
    @MainActor func testSettingUpDark() async { await settingUp(.dark) }
    @MainActor func testOnLight() async { snap(await saved(), .light) }
    @MainActor func testOnDark() async { snap(await saved(), .dark) }
    @MainActor func testNotificationsOffLight() async { snap(await saved(permission: .off), .light) }
    @MainActor func testNotificationsOffDark() async { snap(await saved(permission: .off), .dark) }
    @MainActor func testCouldNotSaveLight() async { snap(await saved(failing: true), .light) }
    @MainActor func testCouldNotSaveDark() async { snap(await saved(failing: true), .dark) }

    @MainActor
    private func model(_ kind: AlertRule.Kind = .thisTrip, server: FakeAlertServer = FakeAlertServer(),
                       permission: NotificationPermission = .allowed) -> AlertSetupViewModel {
        AlertSetupViewModel(
            request: AlertSetupViewModelTests.request(kind), rules: AlertFixtures.rules(server, permission: permission)
        )
    }

    @MainActor
    private func saved(permission: NotificationPermission = .allowed, failing: Bool = false) async -> AlertSetupViewModel {
        let server = FakeAlertServer()
        await server.setFailing(failing)
        let model = self.model(server: server, permission: permission)
        await model.save()
        return model
    }

    /// "Setting up" while the server holds the save, as behind the permission dialog in permission-prompt.png.
    @MainActor
    private func settingUp(_ style: UIUserInterfaceStyle, testName: String = #function) async {
        let server = FakeAlertServer()
        await server.holdSaves()
        let model = self.model(server: server)
        let save = Task { await model.save() }
        await server.waitUntilHolding()
        snap(model, style, testName: testName)
        await server.release()
        await save.value
    }

    @MainActor
    private func snap(_ model: AlertSetupViewModel, _ style: UIUserInterfaceStyle, testName: String = #function, line: UInt = #line) {
        let view = VStack(spacing: 0) {
            Spacer(minLength: 0)
            AlertSetupView(viewModel: model)
                .background {
                    UnevenRoundedRectangle(topLeadingRadius: TTRadius.sheet, topTrailingRadius: TTRadius.sheet)
                        .fill(TTColor.surface)
                        .ignoresSafeArea(edges: .bottom)
                }
        }
        .background(TTColor.canvas)
        .environment(\.timeFormatter, TimeFormatter(format: .twelveHour))
        assertSnapshot(
            of: view,
            as: .image(perceptualPrecision: 0.98, layout: .device(config: .iPhone17Pro), traits: UITraitCollection(userInterfaceStyle: style)),
            testName: testName,
            line: line
        )
    }
}
