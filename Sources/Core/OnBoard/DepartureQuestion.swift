import Foundation

/// "On board?" when an alerted train leaves and no ride is on (TT-231, D110; the Live view canvas's boards 31 to 35). The Live
/// Activity card asks (the alert server's update, with an alert; the app's own, silent, while it is in front), a
/// notification only when there is no card, and Schedule's question strip while Schedule shows. It asks once per train per
/// day: a No on any of them is kept in the declined store (`DetectionStore`), so nothing asks about that train again today,
/// and the automatic ride does not watch it. Not on it and the undo by itself decline a train there too (TT-243, D120).
enum DepartureQuestion {
    /// Where the rider answered.
    enum Surface: String, Sendable {
        case card, notification, schedule
    }

    /// The train was declined today: a No here, Not on it, or the undo by itself.
    static func isDeclined(_ key: TripKey, in defaults: UserDefaults?) -> Bool {
        guard let defaults else { return false }
        return (defaults.stringArray(forKey: DetectionStore.silencedKey) ?? []).contains(entry(key))
    }

    /// No: kept for today, and counted.
    @MainActor
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

/// Schedule's question at departure (TT-231): "On the train to Clarkson?" over Yes and No, in the strip's asking slot.
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

/// The trains declined today (TT-175's No, kept for the departure question since TT-243, D120): "20261127/tripId", under the
/// key `detect.silenced` so declines an older build kept still hold. Readable from any thread: the card's No and Not on it
/// are handled before iOS suspends the app again.
enum DetectionStore {
    static let silencedKey = "detect.silenced"

    /// Adds trains to the declined ones, keeping only the day's: an entry from an earlier service day than the earliest
    /// train added goes.
    static func silence(_ trips: [TripKey], in defaults: UserDefaults) {
        guard let today = trips.map(\.serviceDay.dateKey).min() else { return }
        let stored = (defaults.stringArray(forKey: silencedKey) ?? []).filter { entry in
            entry.split(separator: "/", maxSplits: 1).first.flatMap { Int($0) }.map { $0 >= today } ?? false
        }
        let added = trips.map { "\($0.serviceDay.dateKey)/\($0.tripId)" }
        defaults.set(Array(Set(stored + added)).sorted(), forKey: silencedKey)
    }
}
