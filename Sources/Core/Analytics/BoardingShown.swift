import Foundation

/// `boarding_shown` once per train per day (TT-233, D114): sent the first time a train shows Boarding, on Schedule's card
/// or Trip details' hero, whichever shows it first. The trains already counted are kept for their day, so a redraw, a
/// poll or reopening the app sends nothing more.
@MainActor
struct BoardingShown {
    static let key = "analytics.boardingShown"

    /// Where the rider saw it.
    enum Surface: String, Sendable {
        case schedule, trip
    }

    /// Nil in previews and tests that do not check it: nothing is kept and nothing is counted.
    private let defaults: UserDefaults?

    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
    }

    /// `departure` shows Boarding at `station` (the route's origin id) on `surface` at `now`.
    func shown(_ departure: Departure, station: String, surface: Surface, now: Date) {
        guard let defaults else { return }
        let day = "\(departure.id.serviceDay.dateKey)/"
        let entry = day + departure.id.tripId
        // Only this day's trains are kept, so the list never grows.
        let seen = (defaults.stringArray(forKey: Self.key) ?? []).filter { $0.hasPrefix(day) }
        guard !seen.contains(entry) else { return }
        defaults.set(seen + [entry], forKey: Self.key)
        let minutes = Int((departure.trip.scheduledDeparture.timeIntervalSince(now) / 60).rounded(.down))
        Analytics.track(.boardingShown(station: station, minutesBefore: minutes, surface: surface))
    }
}
