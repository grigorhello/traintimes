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
