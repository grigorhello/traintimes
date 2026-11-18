import CoreLocation
import Foundation
import WeatherKit

/// Apple WeatherKit by the station's coordinates (TT-226, D105): no location permission, no key in the app, no server.
/// The only file that imports WeatherKit. One request brings now, ten days and their hours, from the start of today in
/// Toronto. Needs the WeatherKit capability on the App ID and `com.apple.developer.weatherkit` in the entitlements.
struct WeatherKitProvider: WeatherProviding {
    /// The station's coordinates when the station itself has none (the saved route names its stations only).
    let place: @Sendable (Station) async -> GeoPoint?

    func forecast(for station: Station, now: Date) async throws -> WeatherForecast {
        var found = station.place
        if found == nil { found = await place(station) }
        guard let found else { throw WeatherFailure.noPlace }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = goTimeZone
        let start = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: WeatherRules.forecastDays, to: start) else { throw WeatherFailure.failed }
        let location = CLLocation(latitude: found.latitude, longitude: found.longitude)
        do {
            let (current, hourly, daily) = try await WeatherService.shared.weather(
                for: location,
                including: .current, .hourly(startDate: start, endDate: end), .daily(startDate: start, endDate: end)
            )
            return WeatherForecast(
                fetchedAt: now,
                now: WeatherNow(
                    temperature: current.temperature.converted(to: .celsius).value,
                    apparent: current.apparentTemperature.converted(to: .celsius).value,
                    sky: Self.sky(current.condition),
                    precipitation: Self.falling(current.condition),
                    wind: Self.kmh(current.wind.speed),
                    gust: current.wind.gust.map(Self.kmh) ?? 0,
                    isDaylight: current.isDaylight
                ),
                days: daily.forecast.map { day in
                    WeatherDay(
                        start: day.date,
                        high: day.highTemperature.converted(to: .celsius).value,
                        low: day.lowTemperature.converted(to: .celsius).value,
                        sky: Self.sky(day.condition),
                        precipitation: Self.kind(day.precipitation),
                        precipitationChance: day.precipitationChance,
                        wind: Self.kmh(day.wind.speed),
                        gust: day.wind.gust.map(Self.kmh) ?? 0
                    )
                },
                hours: hourly.forecast.map { hour in
                    WeatherHour(
                        date: hour.date,
                        temperature: hour.temperature.converted(to: .celsius).value,
                        sky: Self.sky(hour.condition),
                        precipitation: Self.kind(hour.precipitation),
                        precipitationChance: hour.precipitationChance,
                        gust: hour.wind.gust.map(Self.kmh) ?? 0,
                        isDaylight: hour.isDaylight
                    )
                }
            )
        } catch is URLError {
            throw WeatherFailure.offline
        } catch {
            throw (error as NSError).domain == NSURLErrorDomain ? WeatherFailure.offline : WeatherFailure.failed
        }
    }

    func attribution() async -> WeatherCredit? {
        guard let attribution = try? await WeatherService.shared.attribution else { return nil }
        return WeatherCredit(
            lightMark: attribution.combinedMarkLightURL, darkMark: attribution.combinedMarkDarkURL, legal: attribution.legalPageURL
        )
    }

    private static func kmh(_ speed: Measurement<UnitSpeed>) -> Double {
        speed.converted(to: .kilometersPerHour).value
    }

    private static func sky(_ condition: WeatherCondition) -> WeatherSky {
        switch condition {
        case .clear, .mostlyClear, .hot, .frigid: .clear
        case .partlyCloudy, .sunShowers, .sunFlurries: .partlyCloudy
        default: .cloudy
        }
    }

    /// What is falling now, by the condition.
    private static func falling(_ condition: WeatherCondition) -> PrecipitationKind {
        switch condition {
        case .drizzle, .rain, .heavyRain, .freezingDrizzle, .freezingRain, .sunShowers, .hail, .isolatedThunderstorms,
             .scatteredThunderstorms, .thunderstorms, .strongStorms, .tropicalStorm, .hurricane:
            .rain
        case .flurries, .snow, .heavySnow, .blizzard, .blowingSnow, .sunFlurries, .sleet, .wintryMix:
            .snow
        default:
            .dry
        }
    }

    private static func kind(_ precipitation: WeatherKit.Precipitation) -> PrecipitationKind {
        switch precipitation {
        case .rain, .hail: .rain
        case .snow, .sleet, .mixed: .snow
        default: .dry
        }
    }
}
