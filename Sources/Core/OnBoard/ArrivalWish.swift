import Foundation

/// The arrival wish (TT-223, D100, the Live view canvas's board 23, ending A): 5 s after the train reaches your stop, the
/// ride screen's "Now" rolls into a short warm line picked at random from a pool for the time of day in Toronto, never the
/// one shown last. Analytics compare the wishes (`arrival_wish_shown`, `arrival_wish_closed`).
struct ArrivalWish: Equatable, Sendable {
    enum Period: String, Sendable {
        case morning, midday, evening, night
    }

    /// How the wish left the screen.
    enum Close: String {
        /// Done tapped.
        case done
        /// The chevron, or the sheet swiped down.
        case dismissed
        /// The app went to the background.
        case leftApp = "left_app"
        /// The ride ended 2 min after your stop and the sheet closed itself.
        case auto
    }

    /// `goodDay`: the analytics value, and the string `wish.goodDay`.
    let id: String
    let period: Period

    /// "Have a good day".
    var text: String { String(localized: String.LocalizationValue("wish.\(id)")) }

    /// Morning 3 AM to 11 AM, midday to 4 PM, evening to 9 PM, night to 3 AM, in Toronto.
    static func period(at date: Date) -> Period {
        switch calendar.component(.hour, from: date) {
        case 3..<11: .morning
        case 11..<16: .midday
        case 16..<21: .evening
        default: .night
        }
    }

    /// The wishes for that moment: the period's, with Friday's from 3 PM and the weekend's on Saturday and Sunday.
    static func pool(at date: Date) -> [String] {
        var pool: [String] = switch period(at: date) {
        case .morning: ["goodDay", "greatDay", "goodOne", "enjoyDay"]
        case .midday: ["goodAfternoon", "enjoyAfternoon", "haveGoodOne", "takeCare"]
        case .evening: ["enjoyEvening", "goodEvening", "restWell", "takeCare"]
        case .night: ["goodNight", "homeSafe", "sleepWell"]
        }
        let parts = calendar.dateComponents([.weekday, .hour], from: date)
        switch parts.weekday ?? 0 {
        case 6 where (parts.hour ?? 0) >= 15: pool += ["enjoyWeekend", "happyFriday"]
        case 7, 1: pool.append("enjoyWeekend")
        default: break
        }
        return pool
    }

    /// A wish from the pool at `date`, never `last`; `index(n)` picks one of n (random in the app, fixed in tests).
    static func pick(at date: Date, after last: String?, index: (Int) -> Int) -> ArrivalWish {
        let all = pool(at: date)
        let fresh = all.filter { $0 != last }
        let choices = fresh.isEmpty ? all : fresh
        let picked = choices[min(max(index(choices.count), 0), choices.count - 1)]
        return ArrivalWish(id: picked, period: period(at: date))
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = goTimeZone
        return calendar
    }
}

/// The wish of the ride on screen, one per ride, and what its analytics need (TT-223, D100). One per app, owned by
/// `OnBoard`. The last wish shown is kept on device (`onboard.lastWish`), so the next ride, demo or real, gets another one,
/// and a ride restored at launch keeps its wish.
@MainActor
final class ArrivalWishes {
    /// The wish takes "Now"'s place this long after the train reached your stop (on the real clock; the demo ride's clock
    /// runs faster, so `OnBoard` scales it).
    static let delay: TimeInterval = 5
    /// `seconds` in `arrival_wish_closed` stops here: the ride ends 2 min after your stop.
    static let maxSeconds = 120
    static let storageKey = "onboard.lastWish"

    private struct Stored: Codable {
        let ride: String
        let wish: String
        let period: String
    }

    private struct Session {
        let ride: String
        let wish: ArrivalWish
        let demo: Bool
        var shownAt: Date?
        var taps = 0
        var closed = false
    }

    private let defaults: UserDefaults?
    private let haptics: any HapticPlaying
    private let index: (Int) -> Int
    private var session: Session?

    /// `defaults` nil keeps nothing on device (previews and tests); `index` picks one of n.
    init(
        defaults: UserDefaults?, haptics: any HapticPlaying,
        index: @escaping (Int) -> Int = { Int.random(in: 0..<max(1, $0)) }
    ) {
        self.defaults = defaults
        self.haptics = haptics
        self.index = index
    }

    /// The wish for `ride` (an id that is the same for the whole ride), picked once from the pool at `arrivedAt`.
    func wish(for ride: String, arrivedAt: Date, demo: Bool) -> ArrivalWish {
        if let session, session.ride == ride { return session.wish }
        let stored = defaults?.data(forKey: Self.storageKey).flatMap { try? JSONDecoder().decode(Stored.self, from: $0) }
        let wish: ArrivalWish
        if let stored, stored.ride == ride, let period = ArrivalWish.Period(rawValue: stored.period) {
            wish = ArrivalWish(id: stored.wish, period: period)
        } else {
            wish = ArrivalWish.pick(at: arrivedAt, after: stored?.wish, index: index)
            if let data = try? JSONEncoder().encode(Stored(ride: ride, wish: wish.id, period: wish.period.rawValue)) {
                defaults?.set(data, forKey: Self.storageKey)
            }
        }
        session = Session(ride: ride, wish: wish, demo: demo)
        return wish
    }

    /// The wish is on screen with the app active: `arrival_wish_shown`, once per ride.
    func shown(now: Date = Date()) {
        guard var current = session, current.shownAt == nil else { return }
        current.shownAt = now
        session = current
        Analytics.track(.arrivalWishShown(current.wish, demo: current.demo))
    }

    /// A tap on the wish: it pops, with a Tick, and nothing else happens.
    func tapped() {
        haptics.play(.tick)
        guard var current = session, current.shownAt != nil, !current.closed else { return }
        current.taps += 1
        session = current
    }

    /// The wish left the screen: `arrival_wish_closed`, the first time only, and only for a wish that was shown.
    func closed(_ close: ArrivalWish.Close, now: Date = Date()) {
        guard var current = session, let shownAt = current.shownAt, !current.closed else { return }
        current.closed = true
        session = current
        let seconds = min(Self.maxSeconds, max(0, Int(now.timeIntervalSince(shownAt))))
        Analytics.track(.arrivalWishClosed(current.wish, close: close, seconds: seconds, taps: current.taps, demo: current.demo))
    }
}
