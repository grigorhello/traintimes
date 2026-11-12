import Foundation

/// The Time format setting (Settings, TT-105). Raw values are what the setting stores on device.
enum TimeFormat: String, CaseIterable, Sendable {
    case device
    case twelveHour
    case twentyFourHour
}

/// The one formatter for every time in the app, in notifications and in VoiceOver (D17).
/// View models get it injected as this protocol so tests can pass a fixed format and locale.
protocol TimeFormatting: Sendable {
    /// Clock time in America/Toronto: "7:32 AM" or "07:32". Also the `%@` value for notification and toast strings.
    func time(_ date: Date) -> String
    /// The next train's relative time: "in N min", or "Departing" under 1 min.
    func relative(until departure: Date, now: Date) -> String
    /// The freshness line: "Updated just now" under 1 min, else "Updated N min ago".
    func updated(at date: Date, now: Date) -> String
}

extension TimeFormatting {
    /// The timeline's rail labels (gridlines and the Now label): the clock time without AM or PM, "7:32" or "07:32".
    func railTime(_ date: Date) -> String {
        let full = time(date)
        return full.split(separator: " ").first.map(String.init) ?? full
    }

    /// A trip's length, the one wording everywhere it shows (TT-157, TT-198, D81): "40 min ride" up to 99 min, then
    /// "1 h 45 min ride" ("2 h ride" on the hour).
    func tripLength(from departure: Date, to arrival: Date) -> String {
        let minutes = max(0, Int((arrival.timeIntervalSince(departure) / 60).rounded()))
        if minutes < 100 {
            return String(format: String(localized: "schedule.trip_minutes"), minutes)
        }
        let (hours, rest) = minutes.quotientAndRemainder(dividingBy: 60)
        if rest == 0 {
            return String(format: String(localized: "schedule.trip_hours"), hours)
        }
        return String(format: String(localized: "schedule.trip_hours_minutes"), hours, rest)
    }
}

/// GO trains run on Toronto time, whatever time zone the phone is in (D17).
let goTimeZone = TimeZone(identifier: "America/Toronto")!

struct TimeFormatter: TimeFormatting {
    var format: TimeFormat
    /// Only read in `.device` mode, for the device 12/24-hour setting.
    var locale: Locale = .autoupdatingCurrent

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = goTimeZone
        calendar.locale = Locale(identifier: "en_US_POSIX") // fixed "AM" / "PM" symbols
        return calendar
    }

    var usesTwentyFourHour: Bool {
        switch format {
        case .twelveHour: false
        case .twentyFourHour: true
        case .device: locale.hourCycle == .zeroToTwentyThree || locale.hourCycle == .oneToTwentyFour
        }
    }

    func time(_ date: Date) -> String {
        let calendar = calendar
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let hour = parts.hour ?? 0
        let minute = parts.minute ?? 0
        if usesTwentyFourHour {
            return String(format: "%02d:%02d", hour, minute)
        }
        let hour12 = hour % 12 == 0 ? 12 : hour % 12
        let period = hour < 12 ? calendar.amSymbol : calendar.pmSymbol
        return String(format: "%d:%02d %@", hour12, minute, period)
    }

    func relative(until departure: Date, now: Date) -> String {
        let minutes = Int(departure.timeIntervalSince(now) / 60)
        if minutes < 1 {
            return String(localized: "schedule.departing")
        }
        return String(format: String(localized: "schedule.in_minutes"), minutes)
    }

    func updated(at date: Date, now: Date) -> String {
        let minutes = Int(now.timeIntervalSince(date) / 60)
        if minutes < 1 {
            return String(localized: "schedule.updated_just_now")
        }
        let duration = String(format: String(localized: "schedule.minutes_ago"), minutes)
        return String(format: String(localized: "schedule.updated_ago"), duration)
    }
}
