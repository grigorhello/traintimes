import SnapshotTesting
import SwiftUI
import XCTest
@testable import TrainTimes

/// The Alerts tab against design/frames/alerts.png, light and dark, and every rule state: Review needed, Could not save,
/// Setting up, On and Paused, then notifications turned off (alerts-off.png, TT-169): the card on top and Not delivering on the
/// rows that are on. The empty state (alerts-empty.png) is `AppShellSnapshotTests.testAlertsTab…`. Drawn in the host app's
/// key window, in the tab view, as on the simulator; the card's bell does not shake.
final class AlertsSnapshotTests: XCTestCase {
    @MainActor func testAlertsLight() async throws { snap(try await frame(), .light) }
    @MainActor func testAlertsDark() async throws { snap(try await frame(), .dark) }
    @MainActor func testRuleStatesLight() async throws { try await ruleStates(.light) }
    @MainActor func testRuleStatesDark() async throws { try await ruleStates(.dark) }
    @MainActor func testNotificationsOffLight() async throws { snap(try await notificationsOff(), .light) }
    @MainActor func testNotificationsOffDark() async throws { snap(try await notificationsOff(), .dark) }

    /// alerts.png: three rules, the two recent updates and the Lakeshore West notice. The rule needing review is listed
    /// first, as the requirements order rows (D44).
    @MainActor
    private func frame() async throws -> some View {
        let rules = await AlertsFixtures.rules(
            FakeAlertServer(), on: [AlertsFixtures.evening, AlertsFixtures.morning], reviewNeeded: [AlertsFixtures.burlington]
        )
        return try await root(rules, updates: AlertsFixtures.updates(), schedule: ScheduleViewModel.loadedFixture(.delayed))
    }

    /// One row per state, with Setting up held on the server while the snapshot draws.
    @MainActor
    private func ruleStates(_ style: UIUserInterfaceStyle, testName: String = #function) async throws {
        let server = FakeAlertServer()
        let rules = await AlertsFixtures.rules(
            server, on: [AlertsFixtures.evening, AlertsFixtures.morning], reviewNeeded: [AlertsFixtures.burlington],
            couldNotSave: [AlertsFixtures.today]
        )
        await server.holdSaves()
        let settingUp = AlertRule(
            id: "settingUp", kind: .thisTrip, trip: AlertFixtures.trip("LW-0758-20261105", departure: "12:58"), route: AlertsFixtures.oakvilleToUnion
        )
        let save = Task { await rules.save(settingUp) }
        await server.waitUntilHolding()
        snap(try await root(rules, updates: AlertsFixtures.updates([])), style, testName: testName)
        await server.release()
        await save.value
    }

    /// alerts-off.png: two rules on and one paused, notifications denied, then the two updates and the notice.
    @MainActor
    private func notificationsOff() async throws -> some View {
        let rules = await AlertsFixtures.rules(
            FakeAlertServer(), permission: .off, on: [AlertsFixtures.evening, AlertsFixtures.morning, AlertsFixtures.today]
        )
        return try await root(rules, updates: AlertsFixtures.updates(), schedule: ScheduleViewModel.loadedFixture(.delayed))
    }

    @MainActor
    private func root(
        _ rules: AlertRules, updates: AlertUpdates, schedule: ScheduleViewModel? = nil
    ) async throws -> some View {
        let router = AppRouter()
        router.selectedTab = .alerts
        var loaded = schedule
        if loaded == nil { loaded = try await ScheduleViewModel.loadedFixture() }
        return RootView(
            router: router, schedule: loaded, settings: AppSettings(defaults: .ephemeral()), bells: AlertBellModel(rules: rules),
            alertUpdates: updates
        )
        // The card's glass button and bell swing are drawn settled: dark glass differs from one run to the next (TT-163).
        .environment(\.rendersGlass, false)
        .environment(\.playsSettingsMotion, false)
    }

    @MainActor
    private func snap(_ view: some View, _ style: UIUserInterfaceStyle, testName: String = #function, line: UInt = #line) {
        layOutOnce(view)
        assertSnapshot(
            of: view,
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
