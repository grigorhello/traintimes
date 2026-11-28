import Foundation

/// What Automatic direction keeps on device (TT-234, D116): the rider's own "off", when the app was last in view, when the
/// route was last chosen by hand, the Undo hour with its two stations, the widgets' morning way, and (TT-236) whether the
/// one-time strip was answered and how many turns the app has made, up to 8. No place and no reading. Times come from the
/// app's clock, passed in. Each value is read from the defaults when asked, so a UI test's launch arguments
/// (`LaunchArguments.noDirectionHolds`) read as cleared for the whole run.
@MainActor
final class DirectionStore {
    static let offKey = "direction.off"
    static let inViewKey = "direction.lastInView"
    static let byHandKey = "direction.byHand"
    static let undoKey = "direction.undo"
    static let morningKey = "direction.morningWay"
    static let stripKey = "direction.stripAnswered"
    static let turnsKey = "direction.turns"
    /// A stored time may be this far ahead of the clock before it counts as kept under a later clock.
    private static let clockSlack: TimeInterval = 60

    /// Nil keeps the values in memory only (previews, the unit test host).
    private let defaults: UserDefaults?
    private var memory: [String: Any] = [:]

    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
    }

    /// The rider turned Automatic direction off. Only the "off" is stored: without it the setting reads on whenever
    /// location is allowed with Precise Location.
    var isOff: Bool {
        get { value(Self.offKey) as? Bool ?? false }
        set { set(newValue ? true : nil, Self.offKey) }
    }

    /// The one-time strip was answered (TT-236): OK, Turn off, or the setting turned off in Settings while it showed.
    var stripAnswered: Bool {
        get { value(Self.stripKey) as? Bool ?? false }
        set { set(newValue ? true : nil, Self.stripKey) }
    }

    /// The turns the app has made by itself, up to `DirectionRule.capsuleTurns` (TT-236): the count only decides whether
    /// "Now from …" shows.
    var turnsCounted: Int { value(Self.turnsKey) as? Int ?? 0 }

    /// The app made a turn by itself: counted, up to `DirectionRule.capsuleTurns`.
    func countTurn() {
        let counted = turnsCounted
        guard counted < DirectionRule.capsuleTurns else { return }
        set(counted + 1, Self.turnsKey)
    }

    /// The app went to the background at `now`.
    func leftView(at now: Date) {
        set(now.timeIntervalSince1970, Self.inViewKey)
    }

    /// The rider chose the route by hand at `now` (the picker, a Recent row, the swap button), or a train's link did.
    func choseByHand(at now: Date) {
        set(now.timeIntervalSince1970, Self.byHandKey)
    }

    /// Whether a route chosen by hand still holds at `now`: until the app has been out of view for more than 10 min
    /// since. Once it has, the choice is let go; so is one kept under a later clock (Settings › Testing › Mock time, set
    /// ahead and turned off again), which would otherwise hold until the real clock caught up.
    func holdsChoice(at now: Date) -> Bool {
        guard let chosen = value(Self.byHandKey) as? Double else { return false }
        let time = now.timeIntervalSince1970
        let lastSeen = max(chosen, value(Self.inViewKey) as? Double ?? chosen)
        if chosen - time > Self.clockSlack || time - lastSeen > DirectionRule.handHold {
            set(nil, Self.byHandKey)
            return false
        }
        return true
    }

    /// Undo: the route is not turned between `route`'s two stations for an hour from `now`.
    func startUndoHour(for route: Route, at now: Date) {
        let until = now.addingTimeInterval(DirectionRule.undoHold).timeIntervalSince1970
        set("\(until)|\(Self.pair(route))", Self.undoKey)
    }

    /// Whether the Undo hour for `route`'s two stations still runs at `now`. An hour with more than an hour left was
    /// started under a later clock (Mock time), and is over.
    func holdsUndo(for route: Route, at now: Date) -> Bool {
        guard let stored = value(Self.undoKey) as? String, let bar = stored.firstIndex(of: "|"),
            let until = Double(stored[..<bar])
        else { return false }
        let left = until - now.timeIntervalSince1970
        return stored[stored.index(after: bar)...] == Self.pair(route) && left > 0
            && left <= DirectionRule.undoHold + Self.clockSlack
    }

    /// The widgets' morning way (D107): the direction a widget with no route of its own shows before 12 PM. Set only by
    /// a route chosen by hand; a turn, Undo, Switch and links leave it.
    var morningWay: WidgetFile.RouteKey? {
        guard let ids = value(Self.morningKey) as? [String], ids.count == 2 else { return nil }
        return WidgetFile.RouteKey(fromId: ids[0], toId: ids[1])
    }

    /// The morning way of a route as it stands at `now`, by D107's rule: the route itself before 12 PM, its reverse after;
    /// 12 PM on the clock, so a route chosen between 12 AM and 3 AM is a morning one (TT-257, D131).
    static func morningWay(of route: Route, at now: Date) -> WidgetFile.RouteKey {
        let key = WidgetFile.RouteKey(fromId: route.from.id, toId: route.to.id)
        return ServiceDay.isBeforeNoon(now) ? key : key.reversed
    }

    /// Stores the morning way of `route`, chosen at `now`.
    func setMorningWay(from route: Route, at now: Date) {
        let way = Self.morningWay(of: route, at: now)
        set([way.fromId, way.toId], Self.morningKey)
    }

    /// The two station ids in a fixed order, so both directions name the same pair.
    private static func pair(_ route: Route) -> String {
        [route.from.id, route.to.id].sorted().joined(separator: "|")
    }

    private func value(_ key: String) -> Any? {
        if let defaults { return defaults.object(forKey: key) }
        return memory[key]
    }

    private func set(_ value: Any?, _ key: String) {
        guard let defaults else {
            memory[key] = value
            return
        }
        if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
    }
}
