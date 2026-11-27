import XCTest
@testable import TrainTimes

/// What Automatic direction keeps on device (TT-234, D116): the rider's "off", the hold of a route chosen by hand, the
/// Undo hour and the widgets' morning way. Times are Toronto's, on Thu Nov 19.
@MainActor
final class DirectionStoreTests: XCTestCase {
    private let route = DirectionFixtures.route
    private let day = ServiceDay(year: 2026, month: 11, day: 19)

    private var turned: Route { Route(from: route.to, to: route.from, line: route.line) }

    /// Oakville to Clarkson: another pair of stations.
    private var other: Route {
        Route(from: route.from, to: Station(id: "CL", name: "Clarkson GO"), line: route.line)
    }

    private func at(_ hour: Int, _ minute: Int = 0, _ second: Int = 0) -> Date {
        day.date(hour: hour, minute: minute).addingTimeInterval(TimeInterval(second))
    }

    // MARK: The rider's "off"

    /// Only the "off" is stored: on is its absence, so the setting reads on whenever location allows.
    func testOnlyTheOffIsStored() {
        let defaults = UserDefaults.ephemeral()
        let store = DirectionStore(defaults: defaults)
        XCTAssertFalse(store.isOff)
        XCTAssertNil(defaults.object(forKey: DirectionStore.offKey))

        store.isOff = true
        XCTAssertTrue(store.isOff)
        XCTAssertEqual(defaults.object(forKey: DirectionStore.offKey) as? Bool, true)

        store.isOff = false
        XCTAssertFalse(store.isOff)
        XCTAssertNil(defaults.object(forKey: DirectionStore.offKey), "on stores nothing")
    }

    // MARK: A route chosen by hand

    func testNoChoiceHoldsNothing() {
        let store = DirectionStore(defaults: nil)
        XCTAssertFalse(store.holdsChoice(at: at(8)))
        store.leftView(at: at(8))
        XCTAssertFalse(store.holdsChoice(at: at(8, 5)))
    }

    /// The choice is kept while the app has been out of view for 10 min or less, and let go after more.
    func testAChoiceIsLetGoAfterMoreThan10MinOutOfView() {
        let store = DirectionStore(defaults: nil)
        store.choseByHand(at: at(8))
        XCTAssertTrue(store.holdsChoice(at: at(8)))

        // The app stays in view for half an hour, then leaves: the 10 min count from there.
        store.leftView(at: at(8, 30))
        XCTAssertTrue(store.holdsChoice(at: at(8, 31)))
        XCTAssertTrue(store.holdsChoice(at: at(8, 40)), "10 min out of view")
        XCTAssertFalse(store.holdsChoice(at: at(8, 40, 1)), "more than 10 min out of view")
        // Let go for good, not only at that moment.
        XCTAssertFalse(store.holdsChoice(at: at(8, 31)))
    }

    /// A choice made after the app was last out of view counts from the choice.
    func testTheTimeOutOfViewCountsFromTheLaterOfTheChoiceAndTheLastLeave() {
        let store = DirectionStore(defaults: nil)
        store.leftView(at: at(6))
        store.choseByHand(at: at(8))
        XCTAssertTrue(store.holdsChoice(at: at(8, 10)))
        XCTAssertFalse(store.holdsChoice(at: at(8, 11)))
    }

    /// Short times away keep the choice, however long ago it was made.
    func testShortTimesAwayKeepTheChoice() {
        let store = DirectionStore(defaults: nil)
        store.choseByHand(at: at(8))
        store.leftView(at: at(8, 5))
        XCTAssertTrue(store.holdsChoice(at: at(8, 14)))
        store.leftView(at: at(8, 20))
        XCTAssertTrue(store.holdsChoice(at: at(8, 29)))
        store.leftView(at: at(9))
        XCTAssertTrue(store.holdsChoice(at: at(9, 9)))
        store.leftView(at: at(9, 30))
        XCTAssertFalse(store.holdsChoice(at: at(9, 41)))
    }

    func testANewChoiceHoldsAgain() {
        let store = DirectionStore(defaults: nil)
        store.choseByHand(at: at(8))
        store.leftView(at: at(8, 1))
        XCTAssertFalse(store.holdsChoice(at: at(9)))

        store.choseByHand(at: at(9, 5))
        XCTAssertTrue(store.holdsChoice(at: at(9, 6)))
    }

    /// A choice kept under a later clock (Mock time set ahead, then turned off) is let go, not held until the real clock
    /// catches up.
    func testAChoiceFromALaterClockIsLetGo() {
        let store = DirectionStore(defaults: nil)
        store.choseByHand(at: at(20))
        XCTAssertFalse(store.holdsChoice(at: at(8)))
        XCTAssertFalse(store.holdsChoice(at: at(20)), "it was let go")

        store.choseByHand(at: at(8, 0, 30))
        XCTAssertTrue(store.holdsChoice(at: at(8)), "half a minute ahead is the same clock")
    }

    // MARK: The Undo hour

    func testNoUndoHoldsNothing() {
        XCTAssertFalse(DirectionStore(defaults: nil).holdsUndo(for: route, at: at(17, 30)))
    }

    /// Undo holds for an hour, for both directions of the two stations.
    func testTheUndoHourHoldsBothDirectionsOfThePair() {
        let store = DirectionStore(defaults: nil)
        store.startUndoHour(for: route, at: at(17, 30))

        XCTAssertTrue(store.holdsUndo(for: route, at: at(17, 30)))
        XCTAssertTrue(store.holdsUndo(for: turned, at: at(17, 30)))
        XCTAssertTrue(store.holdsUndo(for: route, at: at(18, 29, 59)))
        XCTAssertTrue(store.holdsUndo(for: turned, at: at(18, 29, 59)))
    }

    func testTheUndoHourEndsAfterAnHour() {
        let store = DirectionStore(defaults: nil)
        store.startUndoHour(for: turned, at: at(17, 30))

        XCTAssertFalse(store.holdsUndo(for: route, at: at(18, 30)))
        XCTAssertFalse(store.holdsUndo(for: turned, at: at(18, 30)))
        XCTAssertFalse(store.holdsUndo(for: route, at: at(20)))
    }

    /// An Undo hour started under a later clock (Mock time set ahead, then turned off) is over.
    func testAnUndoHourFromALaterClockIsOver() {
        let store = DirectionStore(defaults: nil)
        store.startUndoHour(for: route, at: at(20))
        XCTAssertFalse(store.holdsUndo(for: route, at: at(8)))
        XCTAssertFalse(store.holdsUndo(for: route, at: at(18, 58)), "more than the hour left")
        XCTAssertTrue(store.holdsUndo(for: route, at: at(19, 59, 30)), "half a minute ahead is the same clock")
        XCTAssertTrue(store.holdsUndo(for: route, at: at(20, 30)))
    }

    func testTheUndoHourIsNotForAnotherPair() {
        let store = DirectionStore(defaults: nil)
        store.startUndoHour(for: route, at: at(17, 30))

        XCTAssertFalse(store.holdsUndo(for: other, at: at(17, 31)))
        XCTAssertFalse(store.holdsUndo(for: Route(from: other.to, to: other.from, line: nil), at: at(17, 31)))
        XCTAssertTrue(store.holdsUndo(for: route, at: at(17, 31)), "its own pair still holds")
    }

    /// One Undo hour is kept: a later Undo at another pair takes its place, and a second Undo starts the hour again.
    func testALaterUndoTakesTheHour() {
        let store = DirectionStore(defaults: nil)
        store.startUndoHour(for: route, at: at(17, 30))
        store.startUndoHour(for: route, at: at(18))
        XCTAssertTrue(store.holdsUndo(for: route, at: at(18, 45)))

        store.startUndoHour(for: other, at: at(18, 50))
        XCTAssertTrue(store.holdsUndo(for: other, at: at(18, 55)))
        XCTAssertFalse(store.holdsUndo(for: route, at: at(18, 55)))
    }

    /// The line is not part of the pair: the same two stations hold whatever line the route names.
    func testTheUndoHourGoesByStationIdsOnly() {
        let store = DirectionStore(defaults: nil)
        store.startUndoHour(for: route, at: at(17, 30))
        let plain = Route(from: Station(id: "UN", name: "Union"), to: Station(id: "OA", name: "Oakville"), line: nil)
        XCTAssertTrue(store.holdsUndo(for: plain, at: at(17, 40)))
    }

    // MARK: The morning way

    /// D107's rule at the moment of the choice: the route itself before 12 PM, its reverse after.
    func testTheMorningWayIsTheRouteBeforeNoonAndItsReverseAfter() {
        let there = WidgetFile.RouteKey(fromId: "OA", toId: "UN")
        let back = WidgetFile.RouteKey(fromId: "UN", toId: "OA")

        XCTAssertEqual(DirectionStore.morningWay(of: route, at: at(8)), there)
        XCTAssertEqual(DirectionStore.morningWay(of: route, at: at(11, 59)), there)
        XCTAssertEqual(DirectionStore.morningWay(of: route, at: at(12)), back)
        XCTAssertEqual(DirectionStore.morningWay(of: route, at: at(17, 30)), back)

        // The way home chosen in the evening and the way to work chosen in the morning are one morning way.
        XCTAssertEqual(DirectionStore.morningWay(of: turned, at: at(17, 30)), there)
        XCTAssertEqual(DirectionStore.morningWay(of: turned, at: at(8)), back)
    }

    /// 12 PM on the clock, as the welcome reads it (TT-257, D131): a route chosen at 1 AM, before the service day turns at
    /// 3 AM, is a morning one, not written reversed.
    func testTheMorningWayFollowsTheClocksNoon() {
        let there = WidgetFile.RouteKey(fromId: "OA", toId: "UN")
        XCTAssertEqual(DirectionStore.morningWay(of: route, at: at(0, 30)), there, "12:30 AM is before noon")
        XCTAssertEqual(DirectionStore.morningWay(of: route, at: at(1)), there, "1 AM is before noon")
        XCTAssertEqual(DirectionStore.morningWay(of: route, at: at(3)), there)
    }

    func testTheMorningWayIsStoredFromAChoice() {
        let store = DirectionStore(defaults: nil)
        XCTAssertNil(store.morningWay)

        store.setMorningWay(from: route, at: at(8))
        XCTAssertEqual(store.morningWay, WidgetFile.RouteKey(fromId: "OA", toId: "UN"))

        // The same route chosen in the evening is the way home, so the morning way is its reverse.
        store.setMorningWay(from: route, at: at(18))
        XCTAssertEqual(store.morningWay, WidgetFile.RouteKey(fromId: "UN", toId: "OA"))

        store.setMorningWay(from: other, at: at(9))
        XCTAssertEqual(store.morningWay, WidgetFile.RouteKey(fromId: "OA", toId: "CL"))
    }

    // MARK: Where it is kept

    /// With no defaults the values live in memory, each store its own.
    func testMemoryModeKeepsTheValuesInTheStore() {
        let store = DirectionStore(defaults: nil)
        store.isOff = true
        store.choseByHand(at: at(8))
        store.startUndoHour(for: route, at: at(8))
        store.setMorningWay(from: route, at: at(8))

        XCTAssertTrue(store.isOff)
        XCTAssertTrue(store.holdsChoice(at: at(8, 5)))
        XCTAssertTrue(store.holdsUndo(for: route, at: at(8, 5)))
        XCTAssertEqual(store.morningWay, WidgetFile.RouteKey(fromId: "OA", toId: "UN"))
        store.isOff = false
        XCTAssertFalse(store.isOff)

        let second = DirectionStore(defaults: nil)
        XCTAssertFalse(second.isOff)
        XCTAssertFalse(second.holdsChoice(at: at(8, 5)))
        XCTAssertFalse(second.holdsUndo(for: route, at: at(8, 5)))
        XCTAssertNil(second.morningWay)
    }

    /// A second store on the same defaults reads everything back, as the next launch does.
    func testASecondStoreReadsTheDefaultsBack() {
        let defaults = UserDefaults.ephemeral()
        let first = DirectionStore(defaults: defaults)
        first.isOff = true
        first.choseByHand(at: at(8))
        first.leftView(at: at(8, 20))
        first.startUndoHour(for: route, at: at(8, 10))
        first.setMorningWay(from: route, at: at(8))

        let second = DirectionStore(defaults: defaults)
        XCTAssertTrue(second.isOff)
        XCTAssertTrue(second.holdsChoice(at: at(8, 30)), "10 min since it left view at 8:20")
        XCTAssertTrue(second.holdsUndo(for: turned, at: at(9, 9)))
        XCTAssertFalse(second.holdsUndo(for: turned, at: at(9, 10)))
        XCTAssertEqual(second.morningWay, WidgetFile.RouteKey(fromId: "OA", toId: "UN"))
        XCTAssertFalse(second.holdsChoice(at: at(8, 31)), "more than 10 min since 8:20")

        // What one lets go, the other no longer reads.
        XCTAssertFalse(first.holdsChoice(at: at(8, 21)))
        XCTAssertNil(defaults.object(forKey: DirectionStore.byHandKey))
    }

    /// Each value is read from the defaults when asked, so a value cleared under the store reads as cleared.
    func testValuesAreReadFromTheDefaultsEachTime() {
        let defaults = UserDefaults.ephemeral()
        let store = DirectionStore(defaults: defaults)
        store.isOff = true
        store.choseByHand(at: at(8))
        store.startUndoHour(for: route, at: at(8))
        store.setMorningWay(from: route, at: at(8))
        store.stripAnswered = true
        store.countTurn()

        for key in [
            DirectionStore.offKey, DirectionStore.byHandKey, DirectionStore.undoKey, DirectionStore.morningKey,
            DirectionStore.stripKey, DirectionStore.turnsKey,
        ] {
            defaults.removeObject(forKey: key)
        }
        XCTAssertFalse(store.isOff)
        XCTAssertFalse(store.holdsChoice(at: at(8, 1)))
        XCTAssertFalse(store.holdsUndo(for: route, at: at(8, 1)))
        XCTAssertNil(store.morningWay)
        XCTAssertFalse(store.stripAnswered)
        XCTAssertEqual(store.turnsCounted, 0)
    }

    /// The one-time strip's answer and the app's turns, counted up to 8 (TT-236).
    func testTheStripsAnswerAndTheTurnsCountedUpTo8() {
        for defaults in [UserDefaults.ephemeral(), nil] {
            let store = DirectionStore(defaults: defaults)
            XCTAssertFalse(store.stripAnswered)
            XCTAssertEqual(store.turnsCounted, 0)
            store.stripAnswered = true
            XCTAssertTrue(store.stripAnswered)
            for turn in 1...10 {
                store.countTurn()
                XCTAssertEqual(store.turnsCounted, min(turn, DirectionRule.capsuleTurns))
            }
            XCTAssertEqual(DirectionRule.capsuleTurns, 8)
        }
    }

    /// The store keeps seven values and nothing else: no place and no reading.
    func testTheStoreKeepsNoPlace() {
        let defaults = UserDefaults.ephemeral()
        let before = Set(defaults.dictionaryRepresentation().keys)
        let store = DirectionStore(defaults: defaults)
        store.isOff = true
        store.leftView(at: at(8))
        store.choseByHand(at: at(8))
        store.startUndoHour(for: route, at: at(8))
        store.setMorningWay(from: route, at: at(8))
        store.stripAnswered = true
        store.countTurn()

        let written = Set(defaults.dictionaryRepresentation().keys).subtracting(before)
        XCTAssertEqual(
            written,
            [
                DirectionStore.offKey, DirectionStore.inViewKey, DirectionStore.byHandKey, DirectionStore.undoKey,
                DirectionStore.morningKey, DirectionStore.stripKey, DirectionStore.turnsKey,
            ]
        )
        XCTAssertEqual(defaults.object(forKey: DirectionStore.stripKey) as? Bool, true)
        XCTAssertEqual(defaults.object(forKey: DirectionStore.turnsKey) as? Int, 1)
        XCTAssertEqual(defaults.object(forKey: DirectionStore.inViewKey) as? Double, at(8).timeIntervalSince1970)
        XCTAssertEqual(defaults.object(forKey: DirectionStore.byHandKey) as? Double, at(8).timeIntervalSince1970)
        XCTAssertEqual(defaults.stringArray(forKey: DirectionStore.morningKey), ["OA", "UN"])
        let undo = defaults.string(forKey: DirectionStore.undoKey) ?? ""
        XCTAssertTrue(undo.hasSuffix("|OA|UN"), undo)
    }

    /// A value that is not the store's own reads as none.
    func testValuesItCannotReadCountAsNone() {
        let defaults = UserDefaults.ephemeral()
        let store = DirectionStore(defaults: defaults)

        defaults.set("OA|UN", forKey: DirectionStore.undoKey)
        XCTAssertFalse(store.holdsUndo(for: route, at: at(8)))
        defaults.set("soon|OA|UN", forKey: DirectionStore.undoKey)
        XCTAssertFalse(store.holdsUndo(for: route, at: at(8)))
        defaults.set(["OA"], forKey: DirectionStore.morningKey)
        XCTAssertNil(store.morningWay)
        defaults.set("yesterday", forKey: DirectionStore.byHandKey)
        XCTAssertFalse(store.holdsChoice(at: at(8)))
        // An empty launch argument (`-direction.stripAnswered ""`, `-direction.turns ""`) reads as never answered, none counted.
        defaults.set("", forKey: DirectionStore.stripKey)
        XCTAssertFalse(store.stripAnswered)
        defaults.set("", forKey: DirectionStore.turnsKey)
        XCTAssertEqual(store.turnsCounted, 0)
    }
}
