import Foundation

/// The last forecast per station, kept an hour in memory and on disk (TT-226): one request brings every day, so changing
/// the day never loads. Offline or failed, a forecast saved earlier the same Toronto day still shows.
@MainActor
final class WeatherStore {
    /// A forecast younger than this is used as it is.
    static let maxAge: TimeInterval = 60 * 60
    private static let keyPrefix = "weather.forecast."

    let provider: any WeatherProviding
    private let clock: any AppClock
    /// Nil keeps forecasts in memory only (tests, fixture runs).
    private let defaults: UserDefaults?
    private var memory: [String: WeatherForecast] = [:]

    init(provider: any WeatherProviding, clock: any AppClock, defaults: UserDefaults?) {
        self.provider = provider
        self.clock = clock
        self.defaults = defaults
    }

    /// What can show at once: the fixtures, or a saved forecast from today.
    func immediate(for station: Station) -> WeatherForecast? {
        let now = clock.now
        if let forecast = provider.immediate(for: station, now: now) { return forecast }
        return saved(for: station).flatMap { isSameDay($0.fetchedAt, now) ? $0 : nil }
    }

    /// The station's forecast: the saved one while under an hour old, else a new request; a failed request falls back to
    /// one saved earlier today.
    func forecast(for station: Station) async throws(WeatherFailure) -> WeatherForecast {
        let now = clock.now
        if let forecast = provider.immediate(for: station, now: now) { return forecast }
        let saved = saved(for: station)
        if let saved, now.timeIntervalSince(saved.fetchedAt) < Self.maxAge, now >= saved.fetchedAt { return saved }
        do {
            var fresh = try await provider.forecast(for: station, now: now)
            fresh.fetchedAt = now
            if !fresh.isFixture { save(fresh, for: station) }
            return fresh
        } catch {
            if let saved, isSameDay(saved.fetchedAt, clock.now) { return saved }
            throw (error as? WeatherFailure) ?? .failed
        }
    }

    private func saved(for station: Station) -> WeatherForecast? {
        if let forecast = memory[station.id] { return forecast }
        guard let data = defaults?.data(forKey: Self.keyPrefix + station.id),
              let forecast = try? JSONDecoder().decode(WeatherForecast.self, from: data) else { return nil }
        memory[station.id] = forecast
        return forecast
    }

    private func save(_ forecast: WeatherForecast, for station: Station) {
        memory[station.id] = forecast
        if let data = try? JSONEncoder().encode(forecast) { defaults?.set(data, forKey: Self.keyPrefix + station.id) }
    }

    private func isSameDay(_ a: Date, _ b: Date) -> Bool {
        ServiceDay(calendarDayContaining: a) == ServiceDay(calendarDayContaining: b)
    }
}

/// Made-up weather for previews, the unit test host, UI tests and Demo weather, worked out from `now` so every day of the
/// strip has some: today cloudy with rain from 5 PM, then partly cloudy, snow, clear, windy, cloudy, bitter cold, rain
/// all day, partly cloudy, clear.
struct FixtureWeather: WeatherProviding {
    func forecast(for station: Station, now: Date) async throws -> WeatherForecast { Self.forecast(now: now) }
    func immediate(for station: Station, now: Date) -> WeatherForecast? { Self.forecast(now: now) }
    func attribution() async -> WeatherCredit? { .fixture }

    private struct Pattern {
        let sky: WeatherSky
        let precipitation: PrecipitationKind
        let chance: Double
        /// The wet hours, as hours of the day.
        let wet: ClosedRange<Int>
        let high: Double
        let low: Double
        let wind: Double
        let gust: Double
    }

    private static let patterns: [Pattern] = [
        Pattern(sky: .cloudy, precipitation: .rain, chance: 0.6, wet: 17...23, high: 6, low: 1, wind: 25, gust: 35),
        Pattern(sky: .partlyCloudy, precipitation: .dry, chance: 0.1, wet: 0...0, high: 6, low: 0, wind: 15, gust: 25),
        Pattern(sky: .cloudy, precipitation: .snow, chance: 0.7, wet: 15...23, high: 1, low: -4, wind: 20, gust: 30),
        Pattern(sky: .clear, precipitation: .dry, chance: 0, wet: 0...0, high: 12, low: 3, wind: 10, gust: 20),
        Pattern(sky: .cloudy, precipitation: .dry, chance: 0.2, wet: 0...0, high: 8, low: 2, wind: 35, gust: 60),
        Pattern(sky: .cloudy, precipitation: .dry, chance: 0.2, wet: 0...0, high: 7, low: 2, wind: 15, gust: 25),
        Pattern(sky: .clear, precipitation: .dry, chance: 0, wet: 0...0, high: -8, low: -15, wind: 20, gust: 30),
        Pattern(sky: .cloudy, precipitation: .rain, chance: 0.8, wet: 0...23, high: 9, low: 5, wind: 20, gust: 35),
        Pattern(sky: .partlyCloudy, precipitation: .dry, chance: 0.1, wet: 0...0, high: 10, low: 4, wind: 15, gust: 25),
        Pattern(sky: .clear, precipitation: .dry, chance: 0, wet: 0...0, high: 11, low: 3, wind: 10, gust: 20)
    ]

    static func forecast(now: Date) -> WeatherForecast {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = goTimeZone
        let today = calendar.startOfDay(for: now)
        var days: [WeatherDay] = []
        var hours: [WeatherHour] = []
        for (offset, pattern) in patterns.enumerated() {
            guard let start = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            days.append(
                WeatherDay(
                    start: start, high: pattern.high, low: pattern.low, sky: pattern.sky, precipitation: pattern.precipitation,
                    precipitationChance: pattern.chance, wind: pattern.wind, gust: pattern.gust
                )
            )
            for hour in 0..<24 {
                guard let date = calendar.date(byAdding: .hour, value: hour, to: start) else { continue }
                let isWet = pattern.precipitation != .dry && pattern.wet.contains(hour)
                // Coldest at 3 AM, warmest at 3 PM.
                let warmth = (1 - cos(Double((hour + 21) % 24) / 24 * 2 * .pi)) / 2
                hours.append(
                    WeatherHour(
                        date: date, temperature: pattern.low + (pattern.high - pattern.low) * warmth, sky: pattern.sky,
                        precipitation: isWet ? pattern.precipitation : .dry, precipitationChance: isWet ? pattern.chance : 0.1,
                        gust: pattern.gust, isDaylight: (7..<17).contains(hour)
                    )
                )
            }
        }
        let first = patterns[0]
        let current = WeatherNow(
            temperature: 4, apparent: 1, sky: first.sky, precipitation: .dry, wind: first.wind, gust: first.gust,
            isDaylight: (7..<17).contains(calendar.component(.hour, from: now))
        )
        return WeatherForecast(fetchedAt: now, now: current, days: days, hours: hours, isFixture: true)
    }
}
