import SnapshotTesting
import SwiftUI
import XCTest
@testable import TrainTimes

/// TT-115 states against their frames, light and dark: design/frames/schedule-loading.png, schedule-offline.png
/// (schedule-timeline-offline.png is the same board), the stale and future day freshness variants and the No direct
/// connection card on components.png. No direct trains (schedule-no-trains.png) is ScheduleSnapshotTests' Sun 8 test.
final class ScheduleStatesSnapshotTests: XCTestCase {
    @MainActor func testLoadingLight() async throws { try await snapLoading(.light) }
    @MainActor func testLoadingDark() async throws { try await snapLoading(.dark) }
    @MainActor func testOfflineLight() async throws { snap(try await .loadedFixture(.offline), .light) }
    @MainActor func testOfflineDark() async throws { snap(try await .loadedFixture(.offline), .dark) }
    @MainActor func testStaleLight() async throws { snap(try await .loadedFixture(minutesLater: 5), .light) }
    @MainActor func testStaleDark() async throws { snap(try await .loadedFixture(minutesLater: 5), .dark) }
    @MainActor func testFutureDayLight() async throws { snap(try await .loadedFixture(dayIndex: 1), .light) }
    @MainActor func testFutureDayDark() async throws { snap(try await .loadedFixture(dayIndex: 1), .dark) }
    @MainActor func testNoConnectionLight() async throws { snap(try await noConnection(), .light) }
    @MainActor func testNoConnectionDark() async throws { snap(try await noConnection(), .dark) }

    /// The repository never answers until released, so the first timetable is still loading when the snapshot draws.
    @MainActor
    private func snapLoading(_ style: UIUserInterfaceStyle, testName: String = #function) async throws {
        let fixtures = try FixtureScheduleRepository(bundle: Bundle(for: Self.self))
        let repository = PendingScheduleRepository()
        let model = ScheduleViewModel(route: fixtures.route, repository: repository, clock: FixedClock(now: fixtures.now))
        snap(model, style, testName: testName)
        await repository.release()
    }

    /// Oakville and a station on another line: no line serves both (TT-120 saves such a route with no line).
    @MainActor
    private func noConnection() async throws -> ScheduleViewModel {
        let fixtures = try FixtureScheduleRepository(bundle: Bundle(for: Self.self))
        let route = Route(from: fixtures.route.from, to: Station(id: "BA", name: "Barrie"), line: nil)
        let model = ScheduleViewModel(route: route, repository: fixtures, clock: FixedClock(now: fixtures.now))
        await model.loadIfNeeded()
        return model
    }

    @MainActor
    private func snap(_ schedule: ScheduleViewModel, _ style: UIUserInterfaceStyle, testName: String = #function, line: UInt = #line) {
        let view = RootView(schedule: schedule, settings: AppSettings(defaults: .ephemeral()))
            .environment(\.skeletonPulses, false)
            // The swap button draws its solid fallback: its dark glass is drawn differently from one run to the next and
            // failed these dark states on several branches (TT-166). The tab bar stays glass (glassSnapshotPrecision).
            .environment(\.rendersGlass, false)
        layOutOnce(view)
        assertSnapshot(
            of: view,
            as: .image(
                drawHierarchyInKeyWindow: true,
                precision: glassSnapshotPrecision,
                perceptualPrecision: 0.98,
                layout: .device(config: .iPhone17Pro),
                traits: UITraitCollection(userInterfaceStyle: style)
            ).comparedAsRecorded,
            testName: testName,
            line: line
        )
    }
}

/// Holds every timetable request until `release()`, so a screen stays in its loading state.
private actor PendingScheduleRepository: ScheduleRepository {
    private var isReleased = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func trips(for route: Route, on day: ServiceDay) async throws -> [Trip] {
        if !isReleased {
            await withCheckedContinuation { waiting.append($0) }
        }
        return []
    }

    nonisolated func liveStatus(for route: Route, on day: ServiceDay) async throws -> LiveSnapshot { .empty }
    nonisolated func lineNotices(for line: Line) async throws -> [LineNotice] { [] }

    func release() {
        isReleased = true
        waiting.forEach { $0.resume() }
        waiting.removeAll()
    }
}
