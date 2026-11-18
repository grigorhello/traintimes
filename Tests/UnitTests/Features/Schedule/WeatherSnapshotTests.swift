import SnapshotTesting
import SwiftUI
import XCTest
@testable import TrainTimes

/// TT-226 against the Schedule canvas, light and dark: the tile beside the day strip (board 21, Today with rain later;
/// board 22, another day), every tile state (board 23's left columns) and the sheet for Today and another day (boards 14
/// and 15), on the fixture weather.
final class WeatherSnapshotTests: XCTestCase {
    @MainActor func testScheduleTodayLight() async throws { snapSchedule(try await .loadedFixture(), .light) }
    @MainActor func testScheduleTodayDark() async throws { snapSchedule(try await .loadedFixture(), .dark) }
    @MainActor func testScheduleSaturdayLight() async throws { snapSchedule(try await .loadedFixture(dayIndex: 2), .light) }
    @MainActor func testScheduleSaturdayDark() async throws { snapSchedule(try await .loadedFixture(dayIndex: 2), .dark) }
    @MainActor func testTileStatesLight() { snap(TileStates(), .light) }
    @MainActor func testTileStatesDark() { snap(TileStates(), .dark) }
    @MainActor func testSheetTodayLight() throws { snap(try sheet(dayOffset: 0), .light) }
    @MainActor func testSheetTodayDark() throws { snap(try sheet(dayOffset: 0), .dark) }
    @MainActor func testSheetSaturdayLight() throws { snap(try sheet(dayOffset: 2), .light) }
    @MainActor func testSheetSaturdayDark() throws { snap(try sheet(dayOffset: 2), .dark) }

    @MainActor
    private func sheet(dayOffset: Int) throws -> some View {
        let fixtures = try FixtureScheduleRepository(bundle: Bundle(for: Self.self))
        let today = ServiceDay(calendarDayContaining: fixtures.now)
        let sheet = try XCTUnwrap(
            WeatherSheet.make(
                day: today.adding(days: dayOffset), today: today, now: fixtures.now,
                forecast: FixtureWeather.forecast(now: fixtures.now), station: fixtures.route.from.name,
                formatter: TimeFormatter(format: .twelveHour)
            )
        )
        return VStack {
            WeatherSheetView(sheet: sheet, credit: .fixture)
                .background(TTColor.surface, in: RoundedRectangle(cornerRadius: 38))
                .padding(6)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TTColor.canvas)
    }

    @MainActor
    private func snapSchedule(_ schedule: ScheduleViewModel, _ style: UIUserInterfaceStyle, testName: String = #function) {
        let view = RootView(schedule: schedule, settings: AppSettings(defaults: .ephemeral()))
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
            testName: testName
        )
    }

    @MainActor
    private func snap(_ view: some View, _ style: UIUserInterfaceStyle, testName: String = #function) {
        assertSnapshot(
            of: view,
            as: .image(perceptualPrecision: 0.98, layout: .device(config: .iPhone17Pro), traits: UITraitCollection(userInterfaceStyle: style)),
            testName: testName
        )
    }
}

/// Every tile state, as on board 23.
private struct TileStates: View {
    private let tiles: [WeatherTile] = [
        .shows(icon: .rain, temperature: "4°"),
        .shows(icon: .sun, temperature: "12°"),
        .shows(icon: .cloud, temperature: "7°"),
        .shows(icon: .partlySun, temperature: "6°"),
        .shows(icon: .snow, temperature: "1°"),
        .shows(icon: .wind, temperature: "8°"),
        .shows(icon: .moon, temperature: "\u{2212}12°"),
        .unavailable(.past),
        .loading
    ]

    var body: some View {
        VStack(spacing: TTSpace.s3) {
            ForEach(Array(tiles.enumerated()), id: \.offset) { _, tile in
                WeatherTileView(tile: tile, animates: false) {}
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TTColor.canvas)
    }
}
