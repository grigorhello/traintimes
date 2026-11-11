import Foundation

/// A repeating alert's days in words and the days Repeat starts with (TT-191, D71). ISO weekdays: 1 is Monday, 7 is Sunday.
enum AlertDays {
    /// Monday first, as the day tiles show them.
    static let week = Array(1...7)

    /// The days Repeat starts with: Mon to Fri for a weekday train, that day alone for a weekend one.
    static func repeatDays(for day: ServiceDay) -> [Int] {
        day.isoWeekday <= 5 ? Array(1...5) : [day.isoWeekday]
    }

    /// "Mon to Fri" for three days or more in a row, "Every day", "Sat and Sun" for two, else "Mon, Wed, Fri"; nil with no
    /// day.
    static func summary(of days: [Int]) -> String? {
        let sorted = Array(Set(days)).sorted()
        guard let first = sorted.first, let last = sorted.last else { return nil }
        if sorted.count == 7 { return String(localized: "alert.days.every_day") }
        if sorted.count >= 3, last - first == sorted.count - 1 {
            return String(format: String(localized: "alert.days.range"), shortName(first), shortName(last))
        }
        if sorted.count == 2 {
            return String(format: String(localized: "alert.days.pair"), shortName(first), shortName(last))
        }
        return sorted.map(shortName).joined(separator: ", ")
    }

    /// "Mon".
    static func shortName(_ isoWeekday: Int) -> String { symbols.shortWeekdaySymbols[isoWeekday % 7] }

    /// "Monday", a tile's accessibility label.
    static func fullName(_ isoWeekday: Int) -> String { symbols.weekdaySymbols[isoWeekday % 7] }

    /// Fixed English names, as on the canvas and the day strip (`ServiceDay`); index 0 is Sunday.
    private static var symbols: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }
}
