import Foundation
import Observation
import UIKit

/// The Alert setup sheet (TT-142): a This-trip or Repeat rule for one train, the notification permission asked after the
/// first "Enable alerts", and the rule's state in words. Saving, the device token and the server live in `AlertRules`
/// (TT-141); this model builds the rule and reads its state there, so a denied permission never looks like an active alert.
@Observable @MainActor
final class AlertSetupViewModel {
    /// The rule's state as the sheet shows it (the requirements' rule state table).
    enum SheetState: Equatable {
        case settingUp, on, paused, notificationsOff, reviewNeeded, couldNotSave
    }

    /// The app's page in the Settings app, where notifications are turned back on.
    static let notificationSettingsURL = URL(string: UIApplication.openNotificationSettingsURLString)!
    /// Monday to Sunday as ISO weekdays (1 is Monday), the order of the day chips.
    static let weekdays = Array(1...7)
    /// Monday to Friday, preselected for a new Repeat rule.
    static let workdays: Set<Int> = [1, 2, 3, 4, 5]

    let request: AlertSetupRequest
    /// The segmented control: This trip or Repeat.
    var kind: AlertRule.Kind
    /// The Repeat rule's days, ISO weekdays.
    private(set) var weekdays: Set<Int>
    /// From "Enable alerts" until the save ends, permission dialog included: "Setting up", and taps send nothing more.
    private(set) var isWorking = false

    private let rules: AlertRules

    init(request: AlertSetupRequest, rules: AlertRules) {
        self.request = request
        self.rules = rules
        kind = request.kind
        let repeating = rules.matching(AlertRule(kind: .repeating, trip: request.trip, route: request.route))
        weekdays = repeating.map { Set($0.weekdays) } ?? Self.workdays
    }

    /// The stored rule for this train and the selected kind: the sheet is in Manage mode. A This-trip and a Repeat rule
    /// for the same train are separate rules.
    var rule: AlertRule? {
        rules.matching(AlertRule(kind: kind, trip: request.trip, route: request.route))
    }

    var isManaging: Bool { rule != nil }

    var title: String {
        isManaging ? String(localized: "alert.sheet.manage_title") : String(localized: "alert.sheet.title")
    }

    var buttonTitle: String {
        isManaging ? String(localized: "alert.save") : String(localized: "alert.enable")
    }

    var body: String {
        kind == .repeating ? String(localized: "alert.body.repeat") : String(localized: "alert.body.this_trip")
    }

    var footnote: String {
        kind == .repeating ? String(localized: "alert.footnote.repeat") : String(localized: "alert.footnote.this_trip")
    }

    /// Nil for a new rule, which shows the footnote instead.
    var state: SheetState? {
        if isWorking { return .settingUp }
        guard let rule else { return nil }
        switch rules.state(of: rule) {
        case .settingUp: return .settingUp
        case .on: return rule.paused ? .paused : .on
        case .notificationsOff: return .notificationsOff
        case .reviewNeeded: return .reviewNeeded
        case .couldNotSave: return .couldNotSave
        }
    }

    /// Off while setting up, and for a Repeat rule with no day selected.
    var canSave: Bool {
        state != .settingUp && !(kind == .repeating && weekdays.isEmpty)
    }

    /// "Oakville to Union".
    var routeName: String {
        String(format: String(localized: "schedule.route_title"), request.route.from.name, request.route.to.name)
    }

    /// "7:32 AM train · Thu, Nov 5", or for Repeat "Usual 7:32 AM train · Mon to Fri". The train keeps its scheduled
    /// departure as its name (D9).
    func tripLine(_ formatter: some TimeFormatting) -> String {
        let time = formatter.time(request.trip.scheduledDeparture)
        guard kind == .repeating else {
            let train = String(format: String(localized: "trip.title"), time)
            return String(format: String(localized: "trip.line_day"), train, request.trip.key.serviceDay.shortLabel)
        }
        let train = String(format: String(localized: "alert.usual_train"), time)
        guard let days = Self.summary(of: weekdays) else { return train }
        return String(format: String(localized: "trip.line_day"), train, days)
    }

    func toggle(_ weekday: Int) {
        if weekdays.contains(weekday) {
            weekdays.remove(weekday)
        } else {
            weekdays.insert(weekday)
        }
    }

    /// "Enable alerts", "Save" or "Try again": asks for notification permission the first time, then saves the rule on
    /// device and on the server whatever the answer. Saving the same train again updates its rule.
    func save() async {
        guard canSave else { return }
        isWorking = true
        defer { isWorking = false }
        await rules.requestPermission()
        let existing = rule
        await rules.save(
            AlertRule(
                id: existing?.id ?? UUID().uuidString.lowercased(),
                kind: kind,
                trip: request.trip,
                route: request.route,
                weekdays: weekdays.sorted(),
                paused: existing?.paused ?? false
            )
        )
    }

    func delete() async {
        guard let rule else { return }
        await rules.delete(rule.id)
    }

    /// Reads the permission again when the sheet appears, so Notifications off follows Settings.
    func refresh() async {
        await rules.refreshPermission()
    }
}

// MARK: Weekdays

extension AlertSetupViewModel {
    /// "Mon to Fri" for three days or more in a row, "Every day", else short names ("Sat, Sun"); nil with no day.
    static func summary(of days: Set<Int>) -> String? {
        let sorted = days.sorted()
        guard let first = sorted.first, let last = sorted.last else { return nil }
        if sorted.count == 7 { return String(localized: "alert.days.every_day") }
        if sorted.count >= 3, last - first == sorted.count - 1 {
            return String(format: String(localized: "alert.days.range"), shortName(first), shortName(last))
        }
        return sorted.map(shortName).joined(separator: ", ")
    }

    /// "M", the day chip.
    static func letter(_ weekday: Int) -> String { symbols.veryShortWeekdaySymbols[weekday % 7] }

    /// "Monday", the chip's accessibility label.
    static func fullName(_ weekday: Int) -> String { symbols.weekdaySymbols[weekday % 7] }

    /// "Mon".
    static func shortName(_ weekday: Int) -> String { symbols.shortWeekdaySymbols[weekday % 7] }

    /// Fixed English names, as on the canvas and the day strip (`ServiceDay`); index 0 is Sunday.
    private static var symbols: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }
}
