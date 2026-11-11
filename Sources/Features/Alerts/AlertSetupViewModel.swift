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
    /// The tap that started the save was on a new rule: the sheet keeps "Alert for this train" while it sets up, as in
    /// permission-prompt.png, although the rule is already kept on device.
    private var isEnabling = false
    /// "Enable alerts" saved a new rule that is On: the button shows the check, the sheet holds `confirmHold` and closes
    /// (TT-166). It stays set while the sheet goes, so the sheet does not turn into Manage alert on its way out.
    private(set) var isConfirmed = false
    /// The hold after the check is over: the sheet closes.
    private(set) var isFinished = false

    /// Kavsoft's hold after a confirming action, before moving on (the Motion board).
    static let confirmHold: Duration = .milliseconds(300)

    private let rules: AlertRules
    /// Waits out `confirmHold`; tests pass their own.
    private let hold: @Sendable (Duration) async -> Void

    init(
        request: AlertSetupRequest,
        rules: AlertRules,
        hold: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.request = request
        self.rules = rules
        self.hold = hold
        kind = request.kind
        let repeating = rules.matching(AlertRule(kind: .repeating, trip: request.trip, route: request.route))
        weekdays = repeating.flatMap { $0.kind == .repeating ? Set($0.weekdays) : nil } ?? Self.workdays
    }

    /// The train's alert while the selected kind is its kind: the sheet is in Manage mode. Repeat saved on a train with a
    /// This-trip alert changes that alert under its id (`AlertRules.save`, TT-189), so the train keeps one alert.
    var rule: AlertRule? {
        rules.matching(AlertRule(kind: kind, trip: request.trip, route: request.route)).flatMap { $0.kind == kind ? $0 : nil }
    }

    var isManaging: Bool { isWorking || isConfirmed ? !isEnabling : rule != nil }

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
        return SheetState(rules.state(of: rule), paused: rule.paused)
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
    /// device and on the server whatever the answer. Saving the same train again updates its rule. A new rule that is On
    /// confirms with the check, then the sheet closes after the hold (TT-166); any other outcome stays on the sheet.
    func save() async {
        guard canSave, !isConfirmed else { return }
        isEnabling = rule == nil
        isWorking = true
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
        isWorking = false
        guard isEnabling, state == .on else { return }
        isConfirmed = true
        await hold(Self.confirmHold)
        isFinished = true
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
