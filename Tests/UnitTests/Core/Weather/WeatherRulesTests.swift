import XCTest
@testable import TrainTimes

/// TT-226: the weather tile's icon rule, the sheet's first line, today against another day and the grey tile's reasons.
final class WeatherRulesTests: XCTestCase {
    /// Thu Nov 5, 2026, 7:21 AM in Toronto, the fixture clock.
    private let now = ServiceDay(year: 2026, month: 11, day: 5).date(hour: 7, minute: 21)
    private var today: ServiceDay { ServiceDay(calendarDayContaining: now) }
    private let formatter = TimeFormatter(format: .twelveHour)

    // MARK: Icon

    func testRainLaterTodayShowsRainNow() {
        var forecast = Self.forecast(now: now)
        forecast.hours = forecast.hours.map { hour in
            var hour = hour
            if ServiceDay(calendarDayContaining: hour.date) == today, Self.hour(of: hour.date) >= 17 {
                hour.precipitation = .rain
                hour.precipitationChance = 0.4
            }
            return hour
        }
        XCTAssertEqual(WeatherRules.icon(on: today, in: forecast, today: today, now: now), .rain)
    }

    func testAChanceUnderFortyPercentIsNotRain() {
        var forecast = Self.forecast(now: now)
        forecast.hours = forecast.hours.map { hour in
            var hour = hour
            hour.precipitation = .rain
            hour.precipitationChance = 0.39
            return hour
        }
        XCTAssertEqual(WeatherRules.icon(on: today, in: forecast, today: today, now: now), .cloud)
    }

    func testRainEarlierTodayDoesNotCount() {
        var forecast = Self.forecast(now: now)
        forecast.hours = forecast.hours.map { hour in
            var hour = hour
            if ServiceDay(calendarDayContaining: hour.date) == today, Self.hour(of: hour.date) < 6 {
                hour.precipitation = .rain
                hour.precipitationChance = 0.9
            }
            return hour
        }
        XCTAssertEqual(WeatherRules.icon(on: today, in: forecast, today: today, now: now), .cloud)
    }

    func testSnowAnotherDay() {
        var forecast = Self.forecast(now: now)
        forecast.days[2].precipitation = .snow
        forecast.days[2].precipitationChance = 0.4
        XCTAssertEqual(WeatherRules.icon(on: today.adding(days: 2), in: forecast, today: today, now: now), .snow)
    }

    func testWindFromFiftyKilometresAnHour() {
        var forecast = Self.forecast(now: now)
        forecast.now.gust = 49.9
        XCTAssertEqual(WeatherRules.icon(on: today, in: forecast, today: today, now: now), .cloud)
        forecast.now.gust = 50
        XCTAssertEqual(WeatherRules.icon(on: today, in: forecast, today: today, now: now), .wind)
        forecast.days[1].gust = 50
        XCTAssertEqual(WeatherRules.icon(on: today.adding(days: 1), in: forecast, today: today, now: now), .wind)
    }

    func testTheMoonOnlyTonight() {
        var forecast = Self.forecast(now: now)
        forecast.now.sky = .clear
        forecast.now.isDaylight = false
        XCTAssertEqual(WeatherRules.icon(on: today, in: forecast, today: today, now: now), .moon)
        forecast.days[1].sky = .clear
        XCTAssertEqual(WeatherRules.icon(on: today.adding(days: 1), in: forecast, today: today, now: now), .sun)
        forecast.days[1].sky = .partlyCloudy
        XCTAssertEqual(WeatherRules.icon(on: today.adding(days: 1), in: forecast, today: today, now: now), .partlySun)
    }

    // MARK: Tile

    func testTodayIsNowAndAnotherDayItsHigh() {
        var forecast = Self.forecast(now: now)
        forecast.now.temperature = -12.4
        forecast.days[1].high = 6.5
        XCTAssertEqual(
            WeatherRules.tile(on: today, today: today, now: now, forecast: forecast, failure: nil),
            .shows(icon: .cloud, temperature: "\u{2212}12°")
        )
        XCTAssertEqual(
            WeatherRules.tile(on: today.adding(days: 1), today: today, now: now, forecast: forecast, failure: nil),
            .shows(icon: .cloud, temperature: "7°")
        )
    }

    func testNothingToShowReasons() {
        let forecast = Self.forecast(now: now)
        XCTAssertEqual(WeatherRules.tile(on: today.adding(days: -1), today: today, now: now, forecast: forecast, failure: nil), .unavailable(.past))
        XCTAssertEqual(WeatherRules.tile(on: today.adding(days: 10), today: today, now: now, forecast: forecast, failure: nil), .unavailable(.range))
        XCTAssertEqual(WeatherRules.tile(on: today, today: today, now: now, forecast: nil, failure: .offline), .unavailable(.offline))
        XCTAssertEqual(WeatherRules.tile(on: today, today: today, now: now, forecast: nil, failure: .noPlace), .unavailable(.failed))
        XCTAssertEqual(WeatherRules.tile(on: today, today: today, now: now, forecast: nil, failure: nil), .loading)
    }

    func testNoMinusZero() {
        XCTAssertEqual(WeatherFormat.degrees(-0.4), "0°")
        XCTAssertEqual(WeatherFormat.degrees(-0.6), "\u{2212}1°")
    }

    // MARK: Sheet line

    func testRainFromFivePM() {
        let forecast = FixtureWeather.forecast(now: now)
        let sheet = WeatherSheet.make(day: today, today: today, now: now, forecast: forecast, station: "Oakville GO", formatter: formatter)
        XCTAssertEqual(sheet?.line, "Rain from 5 PM")
        XCTAssertEqual(sheet?.detail, "Cloudy now")
        XCTAssertEqual(sheet?.cue, .rain)
        XCTAssertEqual(sheet?.temperature, "4°")
        XCTAssertEqual(sheet?.facts.map(\.label), ["Feels like", "Wind", "Rain"])
        XCTAssertEqual(sheet?.facts.map(\.value), ["1°", "25 km/h", "60 %"])
        XCTAssertEqual(sheet?.hours.map(\.label), ["Now", "10 AM", "1 PM", "4 PM", "7 PM", "10 PM"])
        XCTAssertEqual(sheet?.hours.last?.icon, .rain)
    }

    func testRainAllDayAndUntil() {
        let forecast = FixtureWeather.forecast(now: now)
        let wet = today.adding(days: 7)
        XCTAssertEqual(
            WeatherSheet.summary(on: wet, in: forecast, today: today, now: now, formatter: formatter).line, "Rain all day"
        )
        var raining = Self.forecast(now: now)
        raining.now.precipitation = .rain
        raining.hours = raining.hours.map { hour in
            var hour = hour
            if ServiceDay(calendarDayContaining: hour.date) == today, Self.hour(of: hour.date) < 11 {
                hour.precipitation = .rain
                hour.precipitationChance = 0.8
            }
            return hour
        }
        let summary = WeatherSheet.summary(on: today, in: raining, today: today, now: now, formatter: formatter)
        XCTAssertEqual(summary.line, "Rain until 11 AM")
        XCTAssertNil(summary.detail)
    }

    func testSnowFromThreePMAnotherDay() {
        let forecast = FixtureWeather.forecast(now: now)
        let sheet = WeatherSheet.make(
            day: today.adding(days: 2), today: today, now: now, forecast: forecast, station: "Oakville GO", formatter: formatter
        )
        XCTAssertEqual(sheet?.line, "Snow from 3 PM")
        XCTAssertEqual(sheet?.cue, .snow)
        XCTAssertEqual(sheet?.dayLabel, "Sat, Nov 7")
        XCTAssertEqual(sheet?.facts.map(\.label), ["Low", "Wind", "Snow"])
        XCTAssertEqual(sheet?.hours.map(\.label), ["6 AM", "9 AM", "12 PM", "3 PM", "6 PM", "9 PM"])
    }

    func testFeelsOnlyWhenBitterAndFiveColder() {
        var forecast = Self.forecast(now: now)
        forecast.now.temperature = -6
        forecast.now.apparent = -10
        XCTAssertEqual(WeatherSheet.summary(on: today, in: forecast, today: today, now: now, formatter: formatter).cue, .plain)
        forecast.now.temperature = -5
        let summary = WeatherSheet.summary(on: today, in: forecast, today: today, now: now, formatter: formatter)
        XCTAssertEqual(summary.cue, .cold)
        XCTAssertEqual(summary.line, "Feels \u{2212}10°")
        forecast.now.apparent = -9
        forecast.now.temperature = -2
        XCTAssertEqual(WeatherSheet.summary(on: today, in: forecast, today: today, now: now, formatter: formatter).cue, .plain)
    }

    func testWindyWithGusts() {
        let forecast = FixtureWeather.forecast(now: now)
        let summary = WeatherSheet.summary(on: today.adding(days: 4), in: forecast, today: today, now: now, formatter: formatter)
        XCTAssertEqual(summary.line, "Windy")
        XCTAssertEqual(summary.detail, "Gusts 60 km/h")
        XCTAssertEqual(summary.cue, .wind)
    }

    func testOtherwiseTheSky() {
        let forecast = FixtureWeather.forecast(now: now)
        let summary = WeatherSheet.summary(on: today.adding(days: 3), in: forecast, today: today, now: now, formatter: formatter)
        XCTAssertEqual(summary.line, "Clear")
        XCTAssertEqual(summary.cue, .plain)
    }

    func testNoSheetForAGreyTile() {
        let forecast = FixtureWeather.forecast(now: now)
        XCTAssertNil(WeatherSheet.make(day: today.adding(days: -1), today: today, now: now, forecast: forecast, station: "", formatter: formatter))
        XCTAssertNil(WeatherSheet.make(day: today.adding(days: 10), today: today, now: now, forecast: forecast, station: "", formatter: formatter))
    }

    // MARK: Helpers

    /// Dry and cloudy everywhere, calm, daytime.
    static func forecast(now: Date) -> WeatherForecast {
        var forecast = FixtureWeather.forecast(now: now)
        forecast.isFixture = false
        forecast.now = WeatherNow(temperature: 4, apparent: 2, sky: .cloudy, precipitation: .dry, wind: 10, gust: 20, isDaylight: true)
        forecast.days = forecast.days.map { day in
            var day = day
            day.sky = .cloudy
            day.precipitation = .dry
            day.precipitationChance = 0
            day.gust = 20
            return day
        }
        forecast.hours = forecast.hours.map { hour in
            var hour = hour
            hour.sky = .cloudy
            hour.precipitation = .dry
            hour.precipitationChance = 0
            hour.gust = 20
            return hour
        }
        return forecast
    }

    static func hour(of date: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = goTimeZone
        return calendar.component(.hour, from: date)
    }
}
