import XCTest
@testable import TrainTimes

/// The haptics map (TT-215, D100): each moment's feel once, at its time, and nothing for the silent ones.
@MainActor
final class HapticMomentsTests: XCTestCase {
    // MARK: The map

    func testEachMomentHasItsFeelAndTime() {
        XCTAssertEqual(HapticMoment.tab.feel, .tick)
        XCTAssertEqual(HapticMoment.day.feel, .tick)
        XCTAssertEqual(HapticMoment.swap.feel, .tap)
        XCTAssertEqual(HapticMoment.swap.delay, .milliseconds(310))
        XCTAssertEqual(HapticMoment.remove.feel, .drop)
        XCTAssertEqual(HapticMoment.confirmed.feel, .done)
        XCTAssertEqual(HapticMoment.late.feel, .warning)
        XCTAssertEqual(HapticMoment.firstTrains.feel, .railJoint)
        XCTAssertEqual(HapticMoment.firstTrains.delay, .milliseconds(260))
        XCTAssertEqual(HapticMoment.onBoard.feel, .railJoint)
        XCTAssertEqual(HapticMoment.onBoard.delay, .zero)
        XCTAssertEqual(HapticMoment.tiles.feel, .bloom)
    }

    func testAMomentWithADelayPlaysAfterIt() async {
        let haptics = FakeHaptics()
        let start = ContinuousClock.now
        await haptics.play(.swap)?.value
        XCTAssertEqual(haptics.played, [.tap])
        XCTAssertGreaterThanOrEqual(haptics.times[0] - start, .milliseconds(310))
    }

    // MARK: Schedule

    func testADayTapTicksAndAProgrammaticSelectIsSilent() async {
        let haptics = FakeHaptics()
        let model = scheduleModel(haptics)
        await model.loadIfNeeded()
        await model.select(model.days[1])
        XCTAssertEqual(haptics.played, [], "opening a notification's day is not a tap")
        await model.dayTapped(model.days[2])
        XCTAssertEqual(haptics.played, [.tick])
    }

    func testSwapTapsWhenTheNamesReachTheirRows() async {
        let haptics = FakeHaptics()
        let model = scheduleModel(haptics)
        await model.loadIfNeeded()
        let start = ContinuousClock.now
        await model.swap()
        await eventually { haptics.played == [.tap] }
        XCTAssertGreaterThanOrEqual(haptics.times[0] - start, .milliseconds(310))
    }

    // MARK: A watched train

    private let day = ServiceDay(year: 2026, month: 11, day: 5)
    private var leaves: Date { day.date(hour: 7, minute: 32) }

    private func train(_ status: TrainStatus, id: String = "LW-0732") -> Departure {
        let trip = Trip(
            key: TripKey(serviceDay: day, tripId: id), scheduledDeparture: leaves,
            scheduledArrival: leaves.addingTimeInterval(40 * 60), platform: .pending, tags: []
        )
        return Departure(trip: trip, status: status, expectedDeparture: nil, expectedArrival: nil)
    }

    private func at(_ minutesBefore: Double) -> Date { leaves.addingTimeInterval(-minutesBefore * 60) }

    func testAWatchedTrainTurningLateWarnsOnce() {
        var feels = WatchedTrainFeels()
        let late = TrainStatus.delayed(minutes: 6, reportedAt: at(20))
        XCTAssertNil(feels.moment(for: [train(.onTime)], now: at(20)) { _ in true }, "first seen: noted only")
        XCTAssertEqual(feels.moment(for: [train(late)], now: at(19)) { _ in true }, .late)
        XCTAssertNil(feels.moment(for: [train(.delayed(minutes: 8, reportedAt: at(18)))], now: at(18)) { _ in true })
        XCTAssertNil(feels.moment(for: [train(.offline)], now: at(17)) { _ in true })
        XCTAssertNil(feels.moment(for: [train(late)], now: at(16)) { _ in true }, "back online, still late: no second warning")
        XCTAssertEqual(feels.moment(for: [train(.cancelled(reportedAt: at(15)))], now: at(15)) { _ in true }, .late)
    }

    func testAnAlreadyLateTrainAndAnUnwatchedOneAreSilent() {
        var feels = WatchedTrainFeels()
        let late = TrainStatus.delayed(minutes: 6, reportedAt: at(20))
        XCTAssertNil(feels.moment(for: [train(late)], now: at(20)) { _ in true })
        XCTAssertNil(feels.moment(for: [train(late)], now: at(19)) { _ in true })
        var unwatched = WatchedTrainFeels()
        XCTAssertNil(unwatched.moment(for: [train(.onTime)], now: at(20)) { _ in false })
        XCTAssertNil(unwatched.moment(for: [train(late)], now: at(19)) { _ in false })
    }

    func testAWatchedTrainBoardingPlaysRailJointOnce() {
        var feels = WatchedTrainFeels()
        XCTAssertNil(feels.moment(for: [train(.onTime)], now: at(3)) { _ in true })
        XCTAssertEqual(feels.moment(for: [train(.onTime)], now: at(1.9)) { _ in true }, .boarding)
        XCTAssertNil(feels.moment(for: [train(.onTime)], now: at(1)) { _ in true })
    }

    /// TT-233 (D114): Boarding is the train standing at its platform, so the Rail joint plays then, once, though the
    /// position goes quiet for a poll and comes back, and not again by the clock in the last 2 min.
    func testAWatchedTrainStandingAtItsPlatformPlaysRailJointAtTheRealMoment() {
        var feels = WatchedTrainFeels()
        func standing(seenMinutesBefore: Double) -> Departure {
            let trip = Trip(
                key: TripKey(serviceDay: day, tripId: "LW-0732"), scheduledDeparture: leaves,
                scheduledArrival: leaves.addingTimeInterval(40 * 60), platform: .published("5"), tags: []
            )
            var departure = Departure(trip: trip, status: .onTime, expectedDeparture: leaves, expectedArrival: nil)
            departure.originFix = OriginFix(metres: 140, reportedAt: at(seenMinutesBefore))
            return departure
        }
        XCTAssertNil(feels.moment(for: [train(.onTime)], now: at(20)) { _ in true })
        XCTAssertEqual(feels.moment(for: [standing(seenMinutesBefore: 15.1)], now: at(15)) { _ in true }, .boarding)
        XCTAssertNil(feels.moment(for: [train(.onTime)], now: at(12)) { _ in true }, "the position went quiet")
        XCTAssertNil(feels.moment(for: [standing(seenMinutesBefore: 10.1)], now: at(10)) { _ in true }, "and came back: not again")
        XCTAssertNil(feels.moment(for: [train(.onTime)], now: at(1.9)) { _ in true }, "nor by the clock")
    }

    // MARK: Alerts tab, feedback

    func testRemoveDropsAndUndoTaps() async {
        let haptics = FakeHaptics()
        let rules = await AlertsFixtures.rules(FakeAlertServer(), on: [AlertsFixtures.evening])
        let model = AlertsViewModel(
            rules: rules, updates: await AlertsFixtures.updates([]), clock: FixedClock(now: AlertsFixtures.now),
            actionDuration: .seconds(60), haptics: haptics
        )
        await model.remove("evening")?.value
        XCTAssertEqual(haptics.played, [.drop])
        await model.undo()
        XCTAssertEqual(haptics.played, [.drop, .tap])
    }

    func testFeedbackSentIsDoneAndAFailureIsFail() async {
        let haptics = FakeHaptics()
        let sender = RecordingFeedbackSender()
        let model = FeedbackViewModel(
            sender: sender, context: FeedbackContext(appVersion: "1.0", device: "iPhone18,1", osVersion: "26.1"),
            haptics: haptics
        )
        model.message = "Hello"
        sender.fails = true
        await model.send()
        XCTAssertEqual(haptics.played, [.fail])
        sender.fails = false
        await model.send()
        XCTAssertEqual(haptics.played, [.fail, .done])
    }

    func testNoOnTheQuestionTaps() {
        let haptics = FakeHaptics()
        let onBoard = OnBoard(app: nil, haptics: haptics)
        onBoard.decline()
        XCTAssertEqual(haptics.played, [.tap])
    }

    // MARK: Helpers

    private func eventually(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<300 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out", file: file, line: line)
    }

    private func scheduleModel(_ haptics: FakeHaptics) -> ScheduleViewModel {
        let trips = [train(.onTime).trip]
        let route = AlertFixtures.route
        return ScheduleViewModel(
            route: route, repository: StubScheduleRepository(tripList: trips, live: .empty, stopList: []),
            clock: FixedClock(now: at(30)), haptics: haptics
        )
    }
}
