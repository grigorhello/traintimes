import Foundation

/// How long and how often the ride screen was on screen during one ride (TT-224, D106): `ride_ended`'s `watched_seconds`
/// and `opens`. Seconds count on the real clock, also on the demo ride's faster one.
struct RideWatch: Equatable, Sendable {
    private(set) var opens = 0
    private var total: TimeInterval = 0
    private var since: Date?

    /// The ride screen opened.
    mutating func opened() { opens += 1 }

    /// The ride screen is on screen with the app active from `now`, or stops being so.
    mutating func watching(_ isWatching: Bool, at now: Date) {
        if isWatching {
            if since == nil { since = now }
        } else if let since {
            total += max(0, now.timeIntervalSince(since))
            self.since = nil
        }
    }

    /// Whole seconds watched until `now`.
    func seconds(at now: Date) -> Int {
        let running = since.map { max(0, now.timeIntervalSince($0)) } ?? 0
        return Int((total + running).rounded(.down))
    }
}

/// The ride screen's feels and watch time (TT-224, D106, Live view boards 20 to 22). While the ride screen is on screen
/// with the app active: a stop passing plays a Tick 320 ms after it (an ambient haptic for the train you are on, D95 rule
/// 6's exception), and your stop becoming the next one plays a Tap instead, once a ride. One feel per event; nothing on
/// first sight, nothing for your stop (the arriving nudge's Done plays there, D66), nothing with the screen away. One per
/// app on `OnBoard.screen`.
@MainActor
final class RideScreen {
    private struct Seen: Equatable {
        let engine: ObjectIdentifier
        let passed: Int
        let yoursIsNext: Bool
    }

    private let haptics: any HapticPlaying
    private let passDelay: Duration
    private weak var engine: RideEngine?
    private var isOpen = false
    private var isActive = true
    private var seen: Seen?
    /// The engines whose Tap has played: once a ride.
    private var tapped: Set<ObjectIdentifier> = []
    private var pending: Task<Void, Never>?

    init(haptics: any HapticPlaying, passDelay: Duration = .milliseconds(Int(RideMotion.passDelay * 1000))) {
        self.haptics = haptics
        self.passDelay = passDelay
    }

    /// The ride screen appeared for `engine`'s ride.
    func opened(_ engine: RideEngine?, now: Date = Date()) {
        close(now: now)
        guard let engine else { return }
        self.engine = engine
        isOpen = true
        seen = nil
        engine.watch.opened()
        engine.watch.watching(isActive, at: now)
    }

    /// The ride screen went away.
    func closed(now: Date = Date()) {
        close(now: now)
    }

    /// The app became active, or left the front.
    func scene(isActive: Bool, now: Date = Date()) {
        self.isActive = isActive
        if !isActive { pending?.cancel() }
        if isOpen { engine?.watch.watching(isActive, at: now) }
    }

    /// The ride as the screen shows it now; called on every redraw that changes it.
    func show(passed: Int, yoursIsNext: Bool, isComplete: Bool) {
        guard isOpen, let engine else { return }
        let now = Seen(engine: ObjectIdentifier(engine), passed: passed, yoursIsNext: yoursIsNext)
        defer { seen = now }
        guard let before = seen, before.engine == now.engine, before != now, isActive, !isComplete else { return }
        if yoursIsNext && !before.yoursIsNext && !tapped.contains(now.engine) {
            tapped.insert(now.engine)
            pending?.cancel()
            haptics.play(.tap)
        } else if passed > before.passed {
            pending?.cancel()
            pending = haptics.play(.tick, after: passDelay)
        }
    }

    private func close(now: Date) {
        pending?.cancel()
        pending = nil
        if isOpen { engine?.watch.watching(false, at: now) }
        isOpen = false
        engine = nil
    }
}
