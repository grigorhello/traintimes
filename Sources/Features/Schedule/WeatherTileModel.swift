import Foundation
import Observation

/// The weather tile at the left of the day strip and its sheet (TT-226, D105): the From station's weather for the selected
/// day. One request per station brings every day, so picking a day never loads; a swap or a new route asks for the new From
/// station. `ScheduleView` calls `refresh(for:)` when Schedule shows, on each return to the foreground and on a route change.
@Observable @MainActor
final class WeatherTileModel {
    private(set) var station: Station?
    private(set) var forecast: WeatherForecast?
    private(set) var failure: WeatherFailure?
    private let store: WeatherStore
    private let clock: any AppClock
    /// `weather_unavailable` is sent at most once per Schedule visit.
    @ObservationIgnored private var reportedUnavailable = false

    init(store: WeatherStore, clock: any AppClock, station: Station? = nil) {
        self.store = store
        self.clock = clock
        self.station = station
        forecast = station.flatMap { store.immediate(for: $0) }
    }

    /// The tile for `day`.
    func tile(on day: ServiceDay) -> WeatherTile {
        let now = clock.now
        guard station != nil else { return .unavailable(.failed) }
        return WeatherRules.tile(
            on: day, today: ServiceDay(calendarDayContaining: now), now: now, forecast: forecast, failure: failure
        )
    }

    /// The sheet for `day`, or nil when the tile is grey.
    func sheet(on day: ServiceDay, formatter: any TimeFormatting) -> WeatherSheet? {
        guard let forecast, let station else { return nil }
        let now = clock.now
        return WeatherSheet.make(
            day: day, today: ServiceDay(calendarDayContaining: now), now: now, forecast: forecast, station: station.name,
            formatter: formatter
        )
    }

    /// Asks for `station`'s weather: at once from the saved forecast when under an hour old, else from the provider.
    func refresh(for station: Station?) async {
        guard let station else {
            self.station = nil
            forecast = nil
            failure = nil
            return
        }
        if station != self.station {
            self.station = station
            forecast = store.immediate(for: station)
            failure = nil
        }
        do throws(WeatherFailure) {
            let fresh = try await store.forecast(for: station)
            guard station == self.station else { return }
            forecast = fresh
            failure = nil
        } catch {
            guard station == self.station else { return }
            forecast = nil
            failure = error
        }
    }

    func attribution() async -> WeatherCredit? {
        await store.provider.attribution()
    }

    // MARK: Analytics

    /// The sheet opened on `day`.
    func opened(_ sheet: WeatherSheet, on day: ServiceDay) {
        let offset = ServiceDay(calendarDayContaining: clock.now).days(to: day)
        Analytics.track(.weatherOpened(dayOffset: offset, cue: sheet.cue))
    }

    /// Schedule showed again: the next grey tile may report once more.
    func visitStarted() {
        reportedUnavailable = false
    }

    /// The tile turned grey for `reason`; reported once per visit.
    func showedUnavailable(_ reason: WeatherUnavailable?) {
        guard let reason, !reportedUnavailable else { return }
        reportedUnavailable = true
        Analytics.track(.weatherUnavailable(reason))
    }
}
