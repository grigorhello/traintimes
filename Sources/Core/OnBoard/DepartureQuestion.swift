import Foundation

/// "On board?" when an alerted train leaves and no ride is on (TT-231, D110; the Live view canvas's boards 31 to 35). The Live
/// Activity card asks (the alert server's update, with an alert; the app's own, silent, while it is in front), a
/// notification only when there is no card, and Schedule's question strip while Schedule shows. It asks once per train per
/// day: a No on any of them is kept with train detection's silenced trains (`DetectionStore.silencedKey`), so neither this
/// question nor detection asks about that train again today.
enum DepartureQuestion {
    /// Where the rider answered.
    enum Surface: String, Sendable {
        case card, notification, schedule
    }

    /// The train was declined today (a No here, or on detection's question).
    static func isDeclined(_ key: TripKey, in defaults: UserDefaults?) -> Bool {
        guard let defaults else { return false }
        return (defaults.stringArray(forKey: DetectionStore.silencedKey) ?? []).contains(entry(key))
    }

    /// No: kept for today, and counted.
    static func decline(_ key: TripKey, in defaults: UserDefaults?, surface: Surface) {
        if let defaults { DetectionStore.silence([key], in: defaults) }
        Analytics.track(.departureQuestionAnswered(yes: false, surface: surface))
    }

    /// Schedule's strip asks about `live` (the Live Activity's train, D74): it has left, no ride runs, and it was not declined.
    static func asks(_ live: LiveDeparture?, isRiding: Bool, isDeclined: Bool) -> Bool {
        guard let live, !isRiding, !isDeclined else { return false }
        return live.phase == .departed
    }

    private static func entry(_ key: TripKey) -> String {
        "\(key.serviceDay.dateKey)/\(key.tripId)"
    }
}

/// Schedule's question at departure (TT-231): "On the train to Clarkson?" over Yes and No, in the detection question's card.
struct DepartureAsk: Equatable {
    let ride: Ride
    let route: Route
    /// The demo departure's train (Settings › Testing): Yes hands over into the demo ride, No is not kept.
    let isDemo: Bool

    init(live: LiveDeparture, route: Route, isDemo: Bool) {
        ride = Ride(trip: live.key, from: route.from.id, to: route.to.id)
        self.route = route
        self.isDemo = isDemo
    }
}
