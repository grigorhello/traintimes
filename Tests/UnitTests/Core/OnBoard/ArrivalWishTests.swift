import XCTest
@testable import TrainTimes

/// TT-223, D103: the arrival wish's pools by time of day in Toronto, the seeded pick that never repeats the last wish, one
/// wish per ride, and its two events.
@MainActor
final class ArrivalWishTests: XCTestCase {
    override func tearDown() async throws {
        Analytics.tracker = nil
        try await super.tearDown()
    }

    /// Wednesday Nov 25, 2026 at that time in Toronto, or another day of that week.
    private func at(_ hours: Int, _ minutes: Int = 0, day: Int = 25) -> Date {
        ServiceDay(year: 2026, month: 11, day: day).gtfsTime(hours * 3600 + minutes * 60)
    }

    func testThePoolFollowsTheTimeOfDay() {
        XCTAssertEqual(ArrivalWish.pool(at: at(7)), ["goodDay", "greatDay", "goodOne", "enjoyDay"])
        XCTAssertEqual(ArrivalWish.pool(at: at(13)), ["goodAfternoon", "enjoyAfternoon", "haveGoodOne", "takeCare"])
        XCTAssertEqual(ArrivalWish.pool(at: at(18)), ["enjoyEvening", "goodEvening", "restWell", "takeCare"])
        XCTAssertEqual(ArrivalWish.pool(at: at(22, 30)), ["goodNight", "homeSafe", "sleepWell"])

        let edges: [(Date, ArrivalWish.Period)] = [
            (at(2, 59), .night), (at(3), .morning), (at(10, 59), .morning), (at(11), .midday), (at(15, 59), .midday),
            (at(16), .evening), (at(20, 59), .evening), (at(21), .night), (at(1, day: 26), .night),
        ]
        for (date, period) in edges {
            XCTAssertEqual(ArrivalWish.period(at: date), period, "\(date)")
        }
    }

    func testFridayAfternoonAndTheWeekendAddTheirWishes() {
        XCTAssertEqual(ArrivalWish.pool(at: at(14, 59, day: 27)).count, 4, "Friday before 3 PM")
        XCTAssertEqual(
            ArrivalWish.pool(at: at(15, day: 27)),
            ["goodAfternoon", "enjoyAfternoon", "haveGoodOne", "takeCare", "enjoyWeekend", "happyFriday"]
        )
        XCTAssertEqual(Array(ArrivalWish.pool(at: at(18, day: 27)).suffix(2)), ["enjoyWeekend", "happyFriday"])
        XCTAssertEqual(ArrivalWish.pool(at: at(10, day: 28)), ["goodDay", "greatDay", "goodOne", "enjoyDay", "enjoyWeekend"])
        XCTAssertEqual(ArrivalWish.pool(at: at(22, day: 29)), ["goodNight", "homeSafe", "sleepWell", "enjoyWeekend"])
    }

    func testThePickIsSeededAndNeverTheLastWish() {
        XCTAssertEqual(ArrivalWish.pick(at: at(7), after: nil, index: { _ in 0 }), ArrivalWish(id: "goodDay", period: .morning))
        XCTAssertEqual(ArrivalWish.pick(at: at(7), after: "goodDay", index: { _ in 0 }).id, "greatDay")
        XCTAssertEqual(ArrivalWish.pick(at: at(7), after: nil, index: { $0 - 1 }).id, "enjoyDay")
        for _ in 0..<50 {
            XCTAssertNotEqual(ArrivalWish.pick(at: at(22), after: "homeSafe", index: { Int.random(in: 0..<$0) }).id, "homeSafe")
        }
        XCTAssertEqual(ArrivalWish(id: "goodDay", period: .morning).text, "Have a good day")
    }

    func testOneWishPerRideAndAnotherOneForTheNextRide() {
        let defaults = UserDefaults.ephemeral()
        let wishes = ArrivalWishes(defaults: defaults, haptics: FakeHaptics(), index: { _ in 0 })
        XCTAssertEqual(wishes.wish(for: "a", arrivedAt: at(7), demo: false).id, "goodDay")
        XCTAssertEqual(wishes.wish(for: "a", arrivedAt: at(7), demo: false).id, "goodDay", "Reopened, the same wish")
        XCTAssertEqual(wishes.wish(for: "b", arrivedAt: at(7), demo: false).id, "greatDay", "The next ride gets another")

        // Relaunched during ride b: the same wish comes back; the ride after it does not repeat it.
        let relaunched = ArrivalWishes(defaults: defaults, haptics: FakeHaptics(), index: { _ in 0 })
        XCTAssertEqual(relaunched.wish(for: "b", arrivedAt: at(7), demo: false).id, "greatDay")
        XCTAssertEqual(relaunched.wish(for: "c", arrivedAt: at(7), demo: false).id, "goodDay")
    }

    func testShownAndClosedAreSentOncePerRide() {
        let analytics = RecordingAnalytics.install()
        let haptics = FakeHaptics()
        let wishes = ArrivalWishes(defaults: nil, haptics: haptics, index: { _ in 1 })
        let wish = wishes.wish(for: "a", arrivedAt: at(18), demo: true)
        wishes.closed(.dismissed, now: at(18))
        XCTAssertTrue(analytics.events.isEmpty, "Nothing closes before it was shown")

        let shownAt = at(18, 1)
        wishes.shown(now: shownAt)
        wishes.shown(now: shownAt.addingTimeInterval(3))
        XCTAssertEqual(analytics.events, [
            AnalyticsEvent("arrival_wish_shown", ["wish": .string("goodEvening"), "period": .string("evening"), "demo": .bool(true)]),
        ])
        XCTAssertEqual(wish.id, "goodEvening")

        wishes.tapped()
        wishes.tapped()
        XCTAssertEqual(haptics.played, [.tick, .tick], "Each tap pops it with a Tick")
        wishes.closed(.leftApp, now: shownAt.addingTimeInterval(7.9))
        wishes.closed(.auto, now: shownAt.addingTimeInterval(60))
        XCTAssertEqual(analytics.events.last, AnalyticsEvent("arrival_wish_closed", [
            "wish": .string("goodEvening"), "close": .string("left_app"), "seconds": .int(7), "taps": .int(2), "demo": .bool(true),
        ]))
        XCTAssertEqual(analytics.names, ["arrival_wish_shown", "arrival_wish_closed"], "Only the first way it left counts")
    }

    func testSecondsStopAtTwoMinutes() {
        let analytics = RecordingAnalytics.install()
        let wishes = ArrivalWishes(defaults: nil, haptics: FakeHaptics(), index: { _ in 0 })
        _ = wishes.wish(for: "a", arrivedAt: at(7), demo: false)
        wishes.shown(now: at(7))
        wishes.closed(.done, now: at(7, 5))
        XCTAssertEqual(analytics.events.last?.properties["seconds"], .int(120))
        XCTAssertEqual(analytics.events.last?.properties["close"], .string("done"))
        XCTAssertEqual(analytics.events.last?.properties["demo"], .bool(false))
    }
}
