import SnapshotTesting
import SwiftUI
import XCTest
@testable import TrainTimes

/// The Alerts tab as one list (TT-193) against the canvas's *Alerts-Tab* frames, light and dark: the list, a row opened in
/// place, the exceptions (Time changed opened, No train today, a switched-off row) with Recent, notifications off with
/// disabled switches, and the empty tab with the next trains. Drawn in the host app's key window, in the tab view, as on
/// the simulator; the card's bell does not shake and the tiles are drawn settled.
final class AlertsSnapshotTests: XCTestCase {
    @MainActor func testListLight() async throws { snap(try await list(), .light) }
    @MainActor func testListDark() async throws { snap(try await list(), .dark) }
    @MainActor func testOpenLight() async throws { snap(try await list(open: "morning"), .light) }
    @MainActor func testOpenDark() async throws { snap(try await list(open: "morning"), .dark) }
    @MainActor func testStatesLight() async throws { snap(try await states(), .light) }
    @MainActor func testStatesDark() async throws { snap(try await states(), .dark) }
    @MainActor func testMutedLight() async throws { snap(try await muted(), .light) }
    @MainActor func testMutedDark() async throws { snap(try await muted(), .dark) }
    @MainActor func testEmptyLight() async throws { snap(try await empty(), .light) }
    @MainActor func testEmptyDark() async throws { snap(try await empty(), .dark) }

    /// *Alerts-Tab* and *-Open*: 7:32 AM Mon to Fri, 8:21 AM today only and 5:10 PM Mon to Thu.
    @MainActor
    private func list(open: AlertRule.ID? = nil) async throws -> some View {
        let evening = AlertRule(
            id: "evening", kind: .repeating, trip: AlertFixtures.trip("LW-1710-20261105", departure: "22:10"),
            route: AlertsFixtures.unionToOakville, weekdays: [1, 2, 3, 4]
        )
        let rules = await AlertsFixtures.rules(FakeAlertServer(), on: [evening, AlertsFixtures.today, AlertsFixtures.morning])
        let model = await AlertsFixtures.model(rules)
        if let open { model.toggleOpen(open) }
        return try await root(model)
    }

    /// *Alerts-Tab-States*: Time changed opened, No train today, a switched-off row, then Recent.
    @MainActor
    private func states() async throws -> some View {
        let server = FakeAlertServer()
        let holiday = AlertRule(
            id: "holiday", kind: .repeating, trip: AlertFixtures.trip("LW-1645-20261105", departure: "21:45"),
            route: AlertsFixtures.unionToOakville, weekdays: [1, 2, 3, 4, 5]
        )
        let rules = await AlertsFixtures.rules(
            server, on: [AlertsFixtures.evening, holiday], reviewNeeded: [AlertsFixtures.morning]
        )
        await server.setStatuses([
            AlertRuleStatus(id: "morning", state: .reviewNeeded),
            AlertRuleStatus(id: "holiday", state: .on, noMatchingTrainOn: "20261105"),
            AlertRuleStatus(id: "evening", state: .on),
        ])
        await rules.refresh()
        let model = await AlertsFixtures.model(rules, updates: await AlertsFixtures.updates())
        model.toggleOpen("morning")
        return try await root(model)
    }

    /// *Alerts-Tab-Muted*: notifications off, the card on top, the switches disabled and no line under the list.
    @MainActor
    private func muted() async throws -> some View {
        let rules = await AlertsFixtures.rules(
            FakeAlertServer(), permission: .off, on: [AlertsFixtures.evening, AlertsFixtures.morning, AlertsFixtures.today]
        )
        return try await root(await AlertsFixtures.model(rules))
    }

    /// *Alerts-Tab-Empty*: the lead, then the next three trains of the fixture route with their bells.
    @MainActor
    private func empty() async throws -> some View {
        let model = await AlertsFixtures.model(AlertFixtures.rules(FakeAlertServer()), nextTrains: AlertsFixtures.nextTrains)
        return try await root(model)
    }

    @MainActor
    private func root(_ model: AlertsViewModel) async throws -> some View {
        let router = AppRouter()
        router.selectedTab = .alerts
        return RootView(
            router: router, schedule: try await ScheduleViewModel.loadedFixture(), settings: AppSettings(defaults: .ephemeral()),
            bells: AlertBellModel(rules: model.rules), alertsModel: model
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
            ).comparedAsRecorded,
            testName: testName,
            line: line
        )
    }
}
