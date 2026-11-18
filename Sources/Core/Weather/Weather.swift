import Foundation

// The weather tile on Schedule (TT-226, D100): the From station's weather for the selected day, from Apple WeatherKit by
// the station's coordinates. These are the app's own types; only `WeatherKitProvider` imports WeatherKit.

/// The sky with nothing falling from it.
enum WeatherSky: String, Codable, Sendable {
    case clear, partlyCloudy, cloudy
}

/// What falls, when something is expected.
enum PrecipitationKind: String, Codable, Sendable {
    case dry, rain, snow
}

/// One hour of the forecast. Temperatures in °C, wind in km/h, chances 0 to 1.
struct WeatherHour: Codable, Hashable, Sendable {
    var date: Date
    var temperature: Double
    var sky: WeatherSky
    var precipitation: PrecipitationKind
    var precipitationChance: Double
    var gust: Double
    var isDaylight: Bool
}

/// One day of the forecast; `start` is its first moment in Toronto.
struct WeatherDay: Codable, Hashable, Sendable {
    var start: Date
    var high: Double
    var low: Double
    var sky: WeatherSky
    var precipitation: PrecipitationKind
    var precipitationChance: Double
    var wind: Double
    var gust: Double

    /// The Toronto calendar day, matched like Schedule's `today`.
    var day: ServiceDay { ServiceDay(calendarDayContaining: start.addingTimeInterval(12 * 3600)) }
}

/// The weather now.
struct WeatherNow: Codable, Hashable, Sendable {
    var temperature: Double
    var apparent: Double
    var sky: WeatherSky
    /// Falling now.
    var precipitation: PrecipitationKind
    var wind: Double
    var gust: Double
    var isDaylight: Bool
}

/// One request's answer for one station: now, the next ten days and their hours.
struct WeatherForecast: Codable, Hashable, Sendable {
    var fetchedAt: Date
    var now: WeatherNow
    var days: [WeatherDay]
    var hours: [WeatherHour]
    /// Made up by `FixtureWeather` (previews, tests, Demo weather): never kept on disk.
    var isFixture = false
}

/// Why no weather came.
enum WeatherFailure: Error, Equatable, Sendable {
    case offline
    case failed
    /// The station has no coordinates.
    case noPlace
}

/// Apple's Weather mark and legal link, which the sheet must show (WeatherKit's attribution rules).
struct WeatherCredit: Equatable, Sendable {
    var lightMark: URL?
    var darkMark: URL?
    var legal: URL

    /// Fixture runs and Demo weather: no mark image, the text stands in.
    static let fixture = WeatherCredit(
        lightMark: nil, darkMark: nil, legal: URL(string: "https://weatherkit.apple.com/legal-attribution.html")!
    )
}

/// Where the weather comes from: WeatherKit in the app, `FixtureWeather` in previews, tests and Demo weather.
protocol WeatherProviding: Sendable {
    func forecast(for station: Station, now: Date) async throws -> WeatherForecast
    /// A forecast available at once, without waiting: the fixtures, so previews and snapshots never show the skeleton.
    func immediate(for station: Station, now: Date) -> WeatherForecast?
    func attribution() async -> WeatherCredit?
}

extension WeatherProviding {
    func immediate(for station: Station, now: Date) -> WeatherForecast? { nil }
}

/// Settings › Testing › Demo weather (TT-226): fixture weather on a real build, for the simulator and screenshots
/// (`-settings.demoWeather on`).
enum DemoWeather {
    static let key = "settings.demoWeather"

    static var isOn: Bool { UserDefaults.standard.string(forKey: key) == "on" }
}

/// The real provider, or the fixtures while Demo weather is on, read on each call.
struct DemoWeatherProvider: WeatherProviding {
    let base: any WeatherProviding
    var isOn: @Sendable () -> Bool = { DemoWeather.isOn }

    func forecast(for station: Station, now: Date) async throws -> WeatherForecast {
        isOn() ? FixtureWeather.forecast(now: now) : try await base.forecast(for: station, now: now)
    }

    func immediate(for station: Station, now: Date) -> WeatherForecast? {
        isOn() ? FixtureWeather.forecast(now: now) : base.immediate(for: station, now: now)
    }

    func attribution() async -> WeatherCredit? {
        isOn() ? .fixture : await base.attribution()
    }
}

// MARK: - The rules

/// What the tile shows.
enum WeatherIcon: String, Equatable, Sendable {
    case sun, moon, partlySun, partlyMoon, cloud, rain, snow, wind
}

/// Why the tile is grey (the `weather_unavailable` reasons).
enum WeatherUnavailable: String, Equatable, Sendable {
    /// A day before today.
    case past
    /// More than `WeatherRules.forecastDays` ahead, or a day the forecast lacks.
    case range
    case offline
    case failed
}

/// The sheet's first line, as `weather_opened` names it.
enum WeatherCue: String, Equatable, Sendable {
    case rain, snow, cold, wind
    /// The sky alone.
    case plain = "none"
}

enum WeatherRules {
    /// Rain or snow counts from this chance on (an hour's for today, the day's for another day).
    static let precipitationChance = 0.4
    /// Windy from gusts of this many km/h.
    static let windyGust = 50.0
    /// "Feels −15°" only when it feels this much colder than it is…
    static let feelsColderBy = 5.0
    /// …and this cold or colder.
    static let bitterFeels = -10.0
    /// Today and the nine days after it.
    static let forecastDays = 10

    /// The forecast's day, if it has it.
    static func day(_ day: ServiceDay, in forecast: WeatherForecast) -> WeatherDay? {
        forecast.days.first { $0.day == day }
    }

    /// The hours of `day`, from the hour `now` is in when `day` is today.
    static func hours(of day: ServiceDay, in forecast: WeatherForecast, today: ServiceDay, now: Date) -> [WeatherHour] {
        let hourStart = now.addingTimeInterval(-3599)
        return forecast.hours.filter { ServiceDay(calendarDayContaining: $0.date) == day && (day != today || $0.date > hourStart) }
    }

    /// The precipitation the day brings, by the 40 % rule: today any hour from now with that chance (or falling now),
    /// another day the day's chance. Snow when that precipitation is snow.
    static func precipitation(on day: ServiceDay, in forecast: WeatherForecast, today: ServiceDay, now: Date) -> PrecipitationKind {
        if day == today {
            if forecast.now.precipitation != .dry { return forecast.now.precipitation }
            let wet = hours(of: day, in: forecast, today: today, now: now).first { $0.precipitationChance >= precipitationChance }
            guard let wet else { return .dry }
            return wet.precipitation == .snow ? .snow : .rain
        }
        guard let weather = self.day(day, in: forecast), weather.precipitationChance >= precipitationChance else { return .dry }
        return weather.precipitation == .snow ? .snow : .rain
    }

    /// The tile's icon: rain or snow, then wind, then the sky (the moon at night, today only). Nil when the day is missing.
    static func icon(on day: ServiceDay, in forecast: WeatherForecast, today: ServiceDay, now: Date) -> WeatherIcon? {
        let isToday = day == today
        guard isToday || self.day(day, in: forecast) != nil else { return nil }
        switch precipitation(on: day, in: forecast, today: today, now: now) {
        case .rain: return .rain
        case .snow: return .snow
        case .dry: break
        }
        let gust = isToday ? forecast.now.gust : self.day(day, in: forecast)?.gust ?? 0
        if gust >= windyGust { return .wind }
        let sky = isToday ? forecast.now.sky : self.day(day, in: forecast)?.sky ?? .cloudy
        return icon(sky, isDaylight: !isToday || forecast.now.isDaylight)
    }

    /// One hour's icon in the sheet, by the same rule.
    static func icon(_ hour: WeatherHour) -> WeatherIcon {
        if hour.precipitationChance >= precipitationChance { return hour.precipitation == .snow ? .snow : .rain }
        if hour.gust >= windyGust { return .wind }
        return icon(hour.sky, isDaylight: hour.isDaylight)
    }

    static func icon(_ sky: WeatherSky, isDaylight: Bool) -> WeatherIcon {
        switch sky {
        case .clear: isDaylight ? .sun : .moon
        case .partlyCloudy: isDaylight ? .partlySun : .partlyMoon
        case .cloudy: .cloud
        }
    }

    /// Today the temperature now, another day its high.
    static func temperature(on day: ServiceDay, in forecast: WeatherForecast, today: ServiceDay) -> Double? {
        day == today ? forecast.now.temperature : self.day(day, in: forecast)?.high
    }

    /// The tile for `day`: grey before today and past the forecast, the skeleton while the first request runs.
    static func tile(on day: ServiceDay, today: ServiceDay, now: Date, forecast: WeatherForecast?, failure: WeatherFailure?) -> WeatherTile {
        if day < today { return .unavailable(.past) }
        if today.days(to: day) >= forecastDays { return .unavailable(.range) }
        guard let forecast else {
            guard let failure else { return .loading }
            return .unavailable(failure == .offline ? .offline : .failed)
        }
        guard let glyph = Self.icon(on: day, in: forecast, today: today, now: now),
              let degrees = Self.temperature(on: day, in: forecast, today: today) else { return .unavailable(.range) }
        return .shows(icon: glyph, temperature: WeatherFormat.degrees(degrees))
    }
}

/// The tile's state.
enum WeatherTile: Equatable, Sendable {
    case loading
    case shows(icon: WeatherIcon, temperature: String)
    case unavailable(WeatherUnavailable)

    var unavailableReason: WeatherUnavailable? {
        if case .unavailable(let reason) = self { return reason }
        return nil
    }
}

enum WeatherFormat {
    /// Whole degrees Celsius with a real minus sign: "−12°", "4°", never "−0°".
    static func degrees(_ value: Double) -> String {
        let whole = Int(value.rounded())
        return whole < 0 ? "\u{2212}\(-whole)°" : "\(whole)°"
    }

    static func speed(_ kmh: Double) -> String {
        String(format: String(localized: "weather.value.speed"), Int(kmh.rounded()))
    }

    static func percent(_ chance: Double) -> String {
        String(format: String(localized: "weather.value.percent"), Int((chance * 100).rounded()))
    }
}

// MARK: - The sheet

/// The small sheet behind the tile: the station and day, the temperature with one line, three facts and six hours.
struct WeatherSheet: Equatable, Sendable {
    struct Fact: Equatable, Sendable {
        let label: String
        let value: String
    }

    struct Hour: Equatable, Sendable {
        let label: String
        let icon: WeatherIcon
        let temperature: String
    }

    let station: String
    let dayLabel: String
    let icon: WeatherIcon
    let temperature: String
    let line: String
    let detail: String?
    let cue: WeatherCue
    let facts: [Fact]
    let hours: [Hour]

    /// The sheet for `day`, or nil when the tile has nothing to show.
    static func make(
        day: ServiceDay, today: ServiceDay, now: Date, forecast: WeatherForecast, station: String, formatter: any TimeFormatting
    ) -> WeatherSheet? {
        guard day >= today, today.days(to: day) < WeatherRules.forecastDays,
              let icon = WeatherRules.icon(on: day, in: forecast, today: today, now: now),
              let temperature = WeatherRules.temperature(on: day, in: forecast, today: today) else { return nil }
        let isToday = day == today
        let weather = WeatherRules.day(day, in: forecast)
        let (line, detail, cue) = summary(on: day, in: forecast, today: today, now: now, formatter: formatter)
        let kind = WeatherRules.precipitation(on: day, in: forecast, today: today, now: now)
        let dayHours = WeatherRules.hours(of: day, in: forecast, today: today, now: now)
        let chance = isToday ? (dayHours.map(\.precipitationChance).max() ?? 0) : (weather?.precipitationChance ?? 0)
        let snows = kind == .snow || (kind == .dry && (isToday ? dayHours.first?.precipitation : weather?.precipitation) == .snow)
        let facts = [
            isToday
                ? Fact(label: String(localized: "weather.fact.feels"), value: WeatherFormat.degrees(forecast.now.apparent))
                : Fact(label: String(localized: "weather.fact.low"), value: weather.map { WeatherFormat.degrees($0.low) } ?? "—"),
            Fact(label: String(localized: "weather.fact.wind"), value: WeatherFormat.speed(isToday ? forecast.now.wind : weather?.wind ?? 0)),
            Fact(label: String(localized: snows ? "weather.fact.snow" : "weather.fact.rain"), value: WeatherFormat.percent(chance))
        ]
        return WeatherSheet(
            station: station,
            dayLabel: isToday ? String(localized: "button.today") : day.shortLabel,
            icon: icon,
            temperature: WeatherFormat.degrees(temperature),
            line: line,
            detail: detail,
            cue: cue,
            facts: facts,
            hours: hours(on: day, in: forecast, today: today, now: now, formatter: formatter)
        )
    }

    /// The first line that applies, with its optional second line and its analytics cue: rain or snow with its time, then
    /// "Feels −15°", then "Windy", then the sky.
    static func summary(
        on day: ServiceDay, in forecast: WeatherForecast, today: ServiceDay, now: Date, formatter: any TimeFormatting
    ) -> (line: String, detail: String?, cue: WeatherCue) {
        let isToday = day == today
        let weather = WeatherRules.day(day, in: forecast)
        let sky = isToday ? forecast.now.sky : weather?.sky ?? .cloudy
        let kind = WeatherRules.precipitation(on: day, in: forecast, today: today, now: now)
        if kind != .dry {
            let line = precipitationLine(kind, on: day, in: forecast, today: today, now: now, formatter: formatter)
            let detail = isToday && forecast.now.precipitation == .dry
                ? String(format: String(localized: "weather.detail.now"), skyWord(sky)) : nil
            return (line, detail, kind == .snow ? .snow : .rain)
        }
        if isToday, forecast.now.apparent <= WeatherRules.bitterFeels,
           forecast.now.temperature - forecast.now.apparent >= WeatherRules.feelsColderBy {
            let line = String(format: String(localized: "weather.line.feels"), WeatherFormat.degrees(forecast.now.apparent))
            return (line, nil, .cold)
        }
        let gust = isToday ? forecast.now.gust : weather?.gust ?? 0
        if gust >= WeatherRules.windyGust {
            let detail = String(format: String(localized: "weather.detail.gusts"), Int(gust.rounded()))
            return (String(localized: "weather.line.windy"), detail, .wind)
        }
        return (skyWord(sky), nil, .plain)
    }

    /// "Rain from 5 PM", "Rain until 2 PM", "Rain all day" (or Snow): the first run of wet hours in the day's window
    /// (today from now). "Rain" alone when only the day's chance says so.
    static func precipitationLine(
        _ kind: PrecipitationKind, on day: ServiceDay, in forecast: WeatherForecast, today: ServiceDay, now: Date,
        formatter: any TimeFormatting
    ) -> String {
        let prefix = kind == .snow ? "snow" : "rain"
        let hours = WeatherRules.hours(of: day, in: forecast, today: today, now: now)
        let wet = hours.enumerated().map { index, hour in
            hour.precipitationChance >= WeatherRules.precipitationChance
                || (index == 0 && day == today && forecast.now.precipitation != .dry)
        }
        guard let first = wet.firstIndex(of: true) else { return String(localized: String.LocalizationValue("weather.sky.\(prefix)")) }
        if first > 0 {
            return String(format: String(localized: String.LocalizationValue("weather.line.\(prefix)_from")), formatter.hourTime(hours[first].date))
        }
        guard let dry = wet.firstIndex(of: false) else {
            return String(localized: String.LocalizationValue("weather.line.\(prefix)_all_day"))
        }
        return String(format: String(localized: String.LocalizationValue("weather.line.\(prefix)_until")), formatter.hourTime(hours[dry].date))
    }

    static func skyWord(_ sky: WeatherSky) -> String {
        switch sky {
        case .clear: String(localized: "weather.sky.clear")
        case .partlyCloudy: String(localized: "weather.sky.partly")
        case .cloudy: String(localized: "weather.sky.cloudy")
        }
    }

    /// Six hours: today from now every 3 h ("Now" first), another day 6 AM to 9 PM.
    static func hours(
        on day: ServiceDay, in forecast: WeatherForecast, today: ServiceDay, now: Date, formatter: any TimeFormatting
    ) -> [Hour] {
        let picks: [(String, WeatherHour)]
        if day == today {
            let upcoming = forecast.hours.filter { $0.date > now.addingTimeInterval(-3599) }.sorted { $0.date < $1.date }
            guard let first = upcoming.first else { return [] }
            picks = (0..<6).compactMap { step in
                let target = first.date.addingTimeInterval(TimeInterval(step * 3 * 3600))
                guard let hour = upcoming.first(where: { abs($0.date.timeIntervalSince(target)) < 60 }) else { return nil }
                return (step == 0 ? String(localized: "weather.hour.now") : formatter.hourTime(hour.date), hour)
            }
        } else {
            let start = day.date(hour: 6, minute: 0)
            picks = (0..<6).compactMap { step in
                let target = start.addingTimeInterval(TimeInterval(step * 3 * 3600))
                guard let hour = forecast.hours.first(where: { abs($0.date.timeIntervalSince(target)) < 60 }) else { return nil }
                return (formatter.hourTime(hour.date), hour)
            }
        }
        return picks.map { Hour(label: $0.0, icon: WeatherRules.icon($0.1), temperature: WeatherFormat.degrees($0.1.temperature)) }
    }
}

extension TimeFormatting {
    /// An hour on the clock, "5 PM" or "17:00": the time without ":00" in the 12-hour clock.
    func hourTime(_ date: Date) -> String {
        time(date).replacingOccurrences(of: ":00 ", with: " ")
    }
}
