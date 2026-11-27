import SnapshotTesting
import SwiftUI
import XCTest
@testable import TrainTimes

/// The Alerts tab as cards (TT-253, D129) against the Alerts canvas's round 2 boards, light and dark: the cards under their
/// routes with the days row and See trains, the states (late, Time changed, switched off, no train on its days),
/// notifications off with crossed bells, offline, and the empty tab with the next trains. Drawn in the host app's key
/// window, in the tab view, as on the simulator; the bell does not shake.
final class AlertsSnapshotTests: XCTestCase {
    @MainActor func testCardsLight() async throws { snap(try await cards(), .light) }
    @MainActor func testCardsDark() async throws { snap(try await cards(), .dark) }
    @MainActor func testStatesLight() async throws { snap(try await states(), .light) }
    @MainActor func testStatesDark() async throws { snap(try await states(), .dark) }
    @MainActor func testMutedLight() async throws { snap(try await muted(), .light) }
    @MainActor func testMutedDark() async throws { snap(try await muted(), .dark) }
    @MainActor func testOfflineLight() async throws { snap(try await offline(), .light) }
    @MainActor func testOfflineDark() async throws { snap(try await offline(), .dark) }
    @MainActor func testEmptyLight() async throws { snap(try await empty(), .light) }
    @MainActor func testEmptyDark() async throws { snap(try await empty(), .dark) }

    /// 7:32 AM Mon to Fri, in 11 min at Platform 2; 8:21 AM once, today; 5:10 PM Mon to Thu from Union.
    @MainActor
    private func cards() async throws -> some View {
        let rules = await AlertsFixtures.rules(FakeAlertServer(), on: [eveningOn, AlertsFixtures.today, AlertsFixtures.morning])
        return try await root(await AlertsFixtures.model(rules, repository: AlertsFixtures.trains(live: ["OA>UN": AlertsFixtures.live()])))
    }

    /// The 7:32 AM 9 min late, Sundays with no train this week, Burlington's train changed, the 5:10 PM switched off.
    @MainActor
    private func states() async throws -> some View {
        let sunday = AlertRule(
            id: "sunday", kind: .repeating, trip: AlertsFixtures.train("LW-0850", "08:50"), route: AlertsFixtures.oakvilleToUnion,
            weekdays: [7]
        )
        let rules = await AlertsFixtures.rules(
            FakeAlertServer(), on: [AlertsFixtures.morning, sunday, AlertsFixtures.evening], reviewNeeded: [AlertsFixtures.burlington]
        )
        let live = AlertsFixtures.live(delays: ["LW-0732": 9])
        return try await root(await AlertsFixtures.model(rules, repository: AlertsFixtures.trains(live: ["OA>UN": live])))
    }

    /// Notifications off: the card on top, every bell crossed.
    @MainActor
    private func muted() async throws -> some View {
        let rules = await AlertsFixtures.rules(
            FakeAlertServer(), permission: .off, on: [eveningOn, AlertsFixtures.morning, AlertsFixtures.today]
        )
        return try await root(await AlertsFixtures.model(rules))
    }

    /// Offline since 6:52 AM: the line under the title, the cards read Scheduled with no countdown.
    @MainActor
    private func offline() async throws -> some View {
        let rules = await AlertsFixtures.rules(FakeAlertServer(), on: [AlertsFixtures.morning, AlertsFixtures.today])
        let live = AlertsFixtures.live(offline: true)
        return try await root(await AlertsFixtures.model(rules, repository: AlertsFixtures.trains(live: ["OA>UN": live])))
    }

    /// The lead, the route, then the next three trains of the fixture route as plain cards with their bells.
    @MainActor
    private func empty() async throws -> some View {
        let model = await AlertsFixtures.model(AlertFixtures.rules(FakeAlertServer()), nextTrains: AlertsFixtures.nextTrains)
        return try await root(model)
    }

    /// 5:10 PM · Union to Oakville, Mon to Thu, switched on.
    @MainActor
    private var eveningOn: AlertRule {
        var rule = AlertsFixtures.evening
        rule.paused = false
        return rule
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
