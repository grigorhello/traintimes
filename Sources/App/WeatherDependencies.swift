import Foundation

extension WeatherTileModel {
    /// The app's weather (TT-226): WeatherKit, kept an hour on device, with Demo weather in TestFlight and Debug builds.
    /// Xcode previews, the unit test host and UI tests get the fixture weather, so they never ask WeatherKit.
    static func app(
        clock: any AppClock, station: Station?, environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> WeatherTileModel {
        #if DEBUG
        if ScheduleDependencies.isFixtureRun(environment) {
            return WeatherTileModel(store: WeatherStore(provider: FixtureWeather(), clock: clock, defaults: nil), clock: clock, station: station)
        }
        #endif
        let live = WeatherKitProvider(place: { station in
            // The saved route names its stations only: their coordinates come from the downloaded GO feed.
            try? await GTFSFeedStore.shared.timetable().stations.first { $0.id == station.id }?.place
        })
        let provider: any WeatherProviding = BuildChannel.showsTesting ? DemoWeatherProvider(base: live) : live
        return WeatherTileModel(store: WeatherStore(provider: provider, clock: clock, defaults: .standard), clock: clock, station: station)
    }
}
