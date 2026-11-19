import Foundation

/// The GO service day (D18): trips after midnight belong to the previous service day and sort after 11:59 PM.
/// The day changes at `cutoffHour` Toronto time (D24). Used by the day strip, trip identity (D9), alerts and the widgets
/// (in `Shared/` since TT-182, so the widget extension compiles it; Codable for the widget file).
struct ServiceDay: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    static let cutoffHour = 3

    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The service day a moment belongs to: before 3:00 AM it is still the previous day.
    init(containing date: Date) {
        let calendar = Self.calendar
        var local = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        if (local.hour ?? 0) < Self.cutoffHour {
            let noon = calendar.date(from: DateComponents(year: local.year, month: local.month, day: local.day, hour: 12))!
            let previous = calendar.date(byAdding: .day, value: -1, to: noon)!
            local = calendar.dateComponents([.year, .month, .day], from: previous)
        }
        self.init(year: local.year!, month: local.month!, day: local.day!)
    }

    /// The calendar day a moment falls on in Toronto, with no 3:00 AM cutoff: Schedule's Today (TT-159, D52). A trip after
    /// midnight still belongs to the service day it started on; only the screen's idea of "today" turns over at midnight.
    init(calendarDayContaining date: Date) {
        let local = Self.calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: local.year!, month: local.month!, day: local.day!)
    }

    /// Wall-clock minutes since the start of this moment's service day: 23:59 is 1439, 00:40 the next morning is 1480.
    /// Sort trips by this, never by raw clock time.
    static func minutesIntoServiceDay(_ date: Date) -> Int {
        let local = calendar.dateComponents([.hour, .minute], from: date)
        let hour = local.hour ?? 0
        return (hour < cutoffHour ? hour + 24 : hour) * 60 + (local.minute ?? 0)
    }

    /// "2026-11-05", the service date half of a trip's identity (D9).
    var description: String { String(format: "%04d-%02d-%02d", year, month, day) }

    static func < (lhs: ServiceDay, rhs: ServiceDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = goTimeZone
        return calendar
    }
}

/// Day strip and freshness labels (TT-112). Weekday and month names are fixed English abbreviations, as on the canvas.
extension ServiceDay {
    /// The service day `days` after this one.
    func adding(days: Int) -> ServiceDay {
        ServiceDay(containing: Self.calendar.date(byAdding: .day, value: days, to: noon)!)
    }

    /// Whole days from this service day to `other`: 1 for the next, -1 for the one before.
    func days(to other: ServiceDay) -> Int {
        Self.calendar.dateComponents([.day], from: noon, to: other.noon).day ?? 0
    }

    /// 1 for Sunday through 7 for Saturday.
    var weekday: Int { Self.calendar.component(.weekday, from: noon) }

    /// "Sun".
    var weekdayShort: String { Self.symbols.shortWeekdaySymbols[weekday - 1] }

    /// "Sunday", as in "No direct trains on Sunday" (TT-115).
    var weekdayName: String { Self.symbols.weekdaySymbols[weekday - 1] }

    /// The day as a Repeat alert's weekdays count it, ISO: 1 is Monday, 7 is Sunday (`weekday` counts from Sunday).
    var isoWeekday: Int { (weekday + 5) % 7 + 1 }

    /// "Sun, Nov 8".
    var shortLabel: String {
        "\(weekdayShort), \(Self.symbols.shortMonthSymbols[month - 1]) \(day)"
    }

    /// Noon in Toronto, safely inside the service day whatever the DST change. GTFS times count from noon minus 12 h.
    var noon: Date {
        Self.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    /// The moment of a wall-clock time on this service day in Toronto; times before 3:00 AM fall on the next calendar day (D24).
    func date(hour: Int, minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = goTimeZone
        let nextDay = hour < Self.cutoffHour ? 1 : 0
        return calendar.date(from: DateComponents(year: year, month: month, day: day + nextDay, hour: hour, minute: minute))!
    }

    /// The moment `minutes` into this service day, as `ServiceDay.minutesIntoServiceDay` counts them: 1480 is 00:40 the
    /// next morning.
    func date(minutesIntoDay minutes: Int) -> Date {
        let hour = minutes / 60
        return date(hour: hour >= 24 ? hour - 24 : hour, minute: minutes % 60)
    }

    /// "20261105", the service date as GTFS and the alert server write it.
    var gtfsDate: String { String(format: "%04d%02d%02d", year, month, day) }

    private static var symbols: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }
}

/// A trip's identity (D9): service date plus the feed's trip id, never departure time.
struct TripKey: Hashable, Sendable {
    let serviceDay: ServiceDay
    let tripId: String
}
