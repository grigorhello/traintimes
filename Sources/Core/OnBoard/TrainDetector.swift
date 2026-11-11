import Foundation
import Observation

/// The trains a phone could be on (TT-175): the GO feed's trips on the Schedule's route, both ways, in the app; the demo's
/// one train in Demo trains › Ride.
protocol TrainCandidatesProviding: Sendable {
    /// The trains on `route`, or on the same two stations the other way, that run at `time`, with their tracks.
    func candidates(on route: Route, at time: Date) async -> [TrainCandidate]
}

/// Train detection in the app (TT-175, Live-Spec "Three doors into a ride", the middle one): while Schedule or Trip details
/// is open and When In Use is already allowed, the phone's fixes run `TrainMatcher` against the trains on the route, and
/// the screen shows its checking strip and its question. It never asks for location, it stops when the screen goes, and it
/// never starts a ride: the rider's Yes does (`OnBoard.accept`). No silences the question's trains for the day.
@Observable @MainActor
final class TrainDetector {
    static let silencedKey = DetectionStore.silencedKey
    static let candidatesInterval: TimeInterval = 60

    /// What the strip or the question shows.
    private(set) var state = TrainMatcher.State.idle

    @ObservationIgnored private var matcher: TrainMatcher
    private let candidates: any TrainCandidatesProviding
    private let location: any LocationProviding
    private let trains: (any TrainPositionProviding)?
    private let clock: any AppClock
    private let defaults: UserDefaults?
    private let tickInterval: Duration?
    private let feedInterval: TimeInterval
    /// The demo stops once it asks, so its question waits for the rider.
    private let watchesWhileAsking: Bool
    @ObservationIgnored private var route: Route?
    @ObservationIgnored private var isWatching = false
    @ObservationIgnored private var feed: [TripKey: TrainPosition] = [:]
    @ObservationIgnored private var lastFeed = Date.distantPast
    @ObservationIgnored private var lastCandidates = Date.distantPast
    /// The trains last kept in `defaults` as not to be asked about today.
    @ObservationIgnored private var saved: Set<TripKey> = []
    /// Each run's number: a run that a newer one replaced (the screen came back before the old task ended) stops quietly.
    @ObservationIgnored private var generation = 0

    /// `tickInterval` nil runs no timer: tests call `tick()` and `receive(_:)` themselves. `defaults` nil keeps no No
    /// past the run.
    init(
        candidates: any TrainCandidatesProviding,
        location: any LocationProviding,
        trains: (any TrainPositionProviding)? = nil,
        clock: any AppClock,
        defaults: UserDefaults?,
        tickInterval: Duration? = .seconds(1),
        feedInterval: TimeInterval = 15,
        watchesWhileAsking: Bool = true
    ) {
        self.candidates = candidates
        self.location = location
        self.trains = trains
        self.clock = clock
        self.defaults = defaults
        self.tickInterval = tickInterval
        self.feedInterval = feedInterval
        self.watchesWhileAsking = watchesWhileAsking
        saved = Self.silencedToday(in: defaults, now: clock.now)
        matcher = TrainMatcher(silenced: saved)
    }

    /// The detector's clock (the demo's own).
    var now: Date { clock.now }

    var isAsking: Bool {
        if case .asking = state { return true }
        return false
    }

    /// The trains not to ask about again today.
    var silenced: Set<TripKey> { matcher.silenced }

    /// Watches until the task is cancelled (Schedule goes, the app goes to the background) or `shouldGoOn` turns false
    /// (a ride started). Does nothing without When In Use: it never asks.
    func run(on route: Route, while shouldGoOn: @escaping @MainActor () -> Bool = { true }) async {
        generation += 1
        let run = generation
        guard shouldGoOn(), await start(on: route), generation == run else { return }
        while !Task.isCancelled, generation == run, isWatching, shouldGoOn() {
            if !watchesWhileAsking, isAsking { break }
            guard let tickInterval else { break }
            try? await Task.sleep(for: tickInterval)
            guard !Task.isCancelled, generation == run else { break }
            await tick()
        }
        guard generation == run else { return }
        stop()
        // A ride started (from the question or from "I'm on board"): a question left up goes with it.
        if !shouldGoOn() { reset() }
    }

    /// Loads the trains and starts the phone's updates; false when location is not allowed.
    func start(on route: Route) async -> Bool {
        guard location.isAuthorized else { return false }
        // A Not me on the background question (TT-176) may have silenced trains since this detector was made.
        let stored = Self.silencedToday(in: defaults, now: clock.now).subtracting(matcher.silenced)
        if !stored.isEmpty {
            matcher.silence(Array(stored))
            saved.formUnion(stored)
            publish()
        }
        if isWatching {
            isWatching = false
            location.stopUpdates()
        }
        if self.route != route {
            matcher = TrainMatcher(silenced: matcher.silenced)
            state = .idle
            lastCandidates = .distantPast
        }
        self.route = route
        isWatching = true
        await refresh()
        guard isWatching else { return false }
        location.startUpdates { [weak self] fix in self?.receive(fix) }
        return true
    }

    func stop() {
        guard isWatching else { return }
        isWatching = false
        location.stopUpdates()
        // A question stays for the rider to answer; the strip goes with the screen.
        if !isAsking { reset() }
    }

    /// The timer: the trains each minute, the feed, and the checks at the clock's time (the timetable moves on, and a
    /// question unanswered for 3 min goes).
    func tick() async {
        guard isWatching else { return }
        await refresh()
        guard isWatching else { return }
        matcher.update(feed: feed, at: clock.now)
        publish()
    }

    /// A fix from the phone.
    func receive(_ fix: LocationFix) {
        guard isWatching, watchesWhileAsking || !isAsking else { return }
        let now = clock.now
        matcher.receive(fix, at: now)
        matcher.update(feed: feed, at: now)
        publish()
    }

    /// No: the question's trains, and every train that fitted with them, are not asked about again today.
    func decline() {
        matcher.decline()
        publish()
    }

    /// Yes: the ride started, so the question goes.
    func accepted() {
        reset()
    }

    /// A new matcher with the same No's; it gets the trains again on the next refresh.
    private func reset() {
        matcher = TrainMatcher(silenced: matcher.silenced)
        lastCandidates = .distantPast
        state = .idle
    }

    private func refresh() async {
        guard let route else { return }
        let now = clock.now
        if now.timeIntervalSince(lastCandidates) >= Self.candidatesInterval {
            lastCandidates = now
            let list = await candidates.candidates(on: route, at: now)
            matcher.setCandidates(list)
        }
        if let trains, clock.now.timeIntervalSince(lastFeed) >= feedInterval {
            lastFeed = clock.now
            var positions: [TripKey: TrainPosition] = [:]
            for candidate in matcher.candidates {
                positions[candidate.trip] = await trains.position(of: candidate.trip)
            }
            feed = positions
        }
    }

    /// The matcher's state to the screen, and its No's (a No, or a question left unanswered) to `defaults` for the day.
    private func publish() {
        if matcher.state != state { state = matcher.state }
        guard matcher.silenced != saved else { return }
        saved = matcher.silenced
        defaults?.set(saved.map { "\($0.serviceDay.dateKey)/\($0.tripId)" }, forKey: Self.silencedKey)
    }

    /// The trains the rider said No to today (`detect.silenced`, "20261127/tripId"); older days are dropped.
    private static func silencedToday(in defaults: UserDefaults?, now: Date) -> Set<TripKey> {
        let today = ServiceDay(containing: now).dateKey
        let stored = defaults?.stringArray(forKey: silencedKey) ?? []
        return Set(stored.compactMap { entry -> TripKey? in
            let parts = entry.split(separator: "/", maxSplits: 1).map(String.init)
            guard parts.count == 2, let date = Int(parts[0]), date == today else { return nil }
            return TripKey(serviceDay: ServiceDay(dateKey: date), tripId: parts[1])
        })
    }
}
