import Foundation

/// The GO service day (D18): trips after midnight belong to the previous service day and sort after 11:59 PM.
/// The day changes at `cutoffHour` Toronto time (D24). Used by the day strip, trip identity (D9) and alerts.
struct ServiceDay: Hashable, Comparable, Sendable, CustomStringConvertible {
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

    /// 1 for Sunday through 7 for Saturday.
    var weekday: Int { Self.calendar.component(.weekday, from: noon) }

    /// "Sun".
    var weekdayShort: String { Self.symbols.shortWeekdaySymbols[weekday - 1] }

    /// "Sunday", as in "No direct trains on Sunday" (TT-115).
    var weekdayName: String { Self.symbols.weekdaySymbols[weekday - 1] }

    /// "Sun, Nov 8".
    var shortLabel: String {
        "\(weekdayShort), \(Self.symbols.shortMonthSymbols[month - 1]) \(day)"
    }

    /// Noon in Toronto, safely inside the service day whatever the DST change. GTFS times count from noon minus 12 h.
    var noon: Date {
        Self.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private static var symbols: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }
}
