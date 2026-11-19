import XCTest
@testable import TrainTimes

/// TT-231 (D110): "On board?" when an alerted train leaves. The rule on the demo departure's clock (the 5:13 PM train, 3 min
/// late from 5:04, so it leaves at 5:16), the asking card's state, Schedule's question with Yes and No, the declined-today
/// rule shared with train detection, and the analytics.
@MainActor
final class DepartureQuestionTests: XCTestCase {
    private let formatter = TimeFormatter(format: .twelveHour)

    override func tearDown() {
        Analytics.tracker = nil
        super.tearDown()
    }

    private func live(at time: Date) -> LiveDeparture? {
        let session = DemoDeparture.Session(day: DepartureRig.day, clock: TestClock(now: time))
        return session.departure(at: time).flatMap { LiveDeparture($0, now: time) }
    }

    // MARK: The rule

    func testAsksAtTheExpectedDepartureNotBefore() throws {
        XCTAssertEqual(try XCTUnwrap(live(at: DepartureRig.time(17, 13, 30))).phase, .boarding, "Late: not at 5:13")
        XCTAssertEqual(try XCTUnwrap(live(at: DepartureRig.time(17, 15, 59))).phase, .boarding)
        let asking = try XCTUnwrap(live(at: DepartureRig.time(17, 16)))
        XCTAssertEqual(asking.phase, .departed, "At the expected 5:16")
        XCTAssertTrue(DepartureQuestion.asks(asking, isRiding: false, isDeclined: false))
        XCTAssertFalse(DepartureQuestion.asks(live(at: DepartureRig.time(17, 15)), isRiding: false, isDeclined: false))
    }

    func testTheQuestionGoesTenMinutesAfterTheDeparture() throws {
        let live = try XCTUnwrap(live(at: DepartureRig.time(17, 16)))
        XCTAssertEqual(live.endsAt, DepartureRig.time(17, 26))
        XCTAssertNotNil(self.live(at: DepartureRig.time(17, 25, 59)))
        XCTAssertNil(self.live(at: DepartureRig.time(17, 26)), "No answer: gone 10 min after it left")
    }

    func testTheQuestionGoesAtYourStopIfSooner() throws {
        let day = DepartureRig.day
        let trip = Trip(
            key: TripKey(serviceDay: day, tripId: "SHORT"), scheduledDeparture: DepartureRig.time(17, 13),
            scheduledArrival: DepartureRig.time(17, 19), platform: .pending, tags: []
        )
        let departure = Departure(trip: trip, status: .scheduled, expectedDeparture: nil, expectedArrival: nil)
        XCTAssertNotNil(LiveDeparture(departure, now: DepartureRig.time(17, 18, 59)))
        XCTAssertNil(LiveDeparture(departure, now: DepartureRig.time(17, 19)), "At your stop, 6 min after it left")
    }

    func testNeverWhileARideRunsOrOnceDeclined() throws {
        let asking = try XCTUnwrap(live(at: DepartureRig.time(17, 17)))
        XCTAssertFalse(DepartureQuestion.asks(asking, isRiding: true, isDeclined: false))
        XCTAssertFalse(DepartureQuestion.asks(asking, isRiding: false, isDeclined: true))
    }

    func testACancelledTrainNeverAsks() {
        let day = DepartureRig.day
        let trip = Trip(
            key: TripKey(serviceDay: day, tripId: "X"), scheduledDeparture: DepartureRig.time(17, 13),
            scheduledArrival: DepartureRig.time(17, 43), platform: .pending, tags: []
        )
        let departure = Departure(trip: trip, status: .cancelled(reportedAt: DepartureRig.time(17, 0)), expectedDeparture: nil, expectedArrival: nil)
        XCTAssertNil(LiveDeparture(departure, now: DepartureRig.time(17, 17)))
    }

    func testOnlyAnAlertedTrainAsks() throws {
        let session = DemoDeparture.Session(day: DepartureRig.day, clock: TestClock(now: DepartureRig.time(17, 17)))
        let departure = try XCTUnwrap(session.departure(at: DepartureRig.time(17, 17)))
        XCTAssertNil(LiveDeparture.earliest(in: [departure], now: DepartureRig.time(17, 17)) { _ in false }, "Alert off")
        XCTAssertNotNil(LiveDeparture.earliest(in: [departure], now: DepartureRig.time(17, 17)) { _ in true })
    }

    // MARK: The card

    func testTheAskingCard() throws {
        let live = try XCTUnwrap(live(at: DepartureRig.time(17, 16, 30)))
        let deviceNow = DepartureRig.time(17, 16, 30).addingTimeInterval(86_400)
        let state = RideActivityAttributes.ContentState(departure: live, now: DepartureRig.time(17, 16, 30), deviceNow: deviceNow, formatter: formatter)
        XCTAssertEqual(state.phase, .departed)
        XCTAssertTrue(state.asks)
        XCTAssertTrue(state.isAsking)
        XCTAssertTrue(state.isDeparture, "Still the departure's card: a tap opens the train")
        XCTAssertEqual(state.title, "5:16 PM departed")
        XCTAssertEqual(state.label, "", "Nothing at the right")
        XCTAssertNil(state.platformNumber)
        XCTAssertNil(state.countdownEnd)
        XCTAssertNil(state.minutes)
        XCTAssertNil(state.delay)
        XCTAssertFalse(state.late)
        XCTAssertFalse(state.isAlert, "The app's own update is silent; the server's carries the alert")
        XCTAssertEqual(
            RideLiveActivity.departureStaleDate(live, now: DepartureRig.time(17, 16, 30), deviceNow: deviceNow).timeIntervalSince(deviceNow),
            9.5 * 60, accuracy: 1, "Ends at 5:26 on the device clock"
        )
    }

    /// The alert server's asking update (server/test/activity.test.ts) decodes.
    func testTheAlertServersAskingStateDecodes() throws {
        let json = """
        {"phase":"departed","title":"7:17 AM departed","now":"","label":"","late":false,"position":0,"isClose":false,
         "updated":"Updated 7:17 AM","asks":true}
        """
        let state = try JSONDecoder().decode(RideActivityAttributes.ContentState.self, from: Data(json.utf8))
        XCTAssertTrue(state.isAsking)
        XCTAssertEqual(state.title, "7:17 AM departed")
        let round = try JSONDecoder().decode(RideActivityAttributes.ContentState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(round, state)
        // The end push's last look, and a push from before TT-231: Departed, no question.
        let departed = try JSONDecoder().decode(RideActivityAttributes.ContentState.self, from: Data(#"{"phase":"departed"}"#.utf8))
        XCTAssertFalse(departed.isAsking)
    }

    func testNoOnTheCardEndsTheIntentsTrain() {
        let attributes = RideActivityAttributes(ride: DemoRide.ride(on: DepartureRig.day), plan: DemoRide.plan(on: DepartureRig.day), line: DemoRide.line)
        let intent = DeclineDepartureIntent(attributes)
        XCTAssertEqual(intent.tripId, DemoRide.tripId)
        XCTAssertEqual(intent.serviceDate, DepartureRig.day.dateKey)
        XCTAssertEqual(intent.originId, "UN")
        XCTAssertEqual(intent.destinationId, "CL")
        let train = DeclinedDeparture(tripId: intent.tripId, serviceDate: intent.serviceDate, originId: "UN", destinationId: "CL")
        XCTAssertEqual(Ride(train), DemoRide.ride(on: DepartureRig.day))
    }

    // MARK: Schedule's question

    private func asking(_ rig: DepartureRig, at time: Date) throws {
        rig.clock.set(time)
        rig.onBoard.updateDepartureAsk(live(at: time), route: DemoRide.route, isDemo: true)
    }

    func testScheduleAsksOnceTheTrainHasLeft() throws {
        let rig = DepartureRig.started(at: DepartureRig.time(17, 15))
        try asking(rig, at: DepartureRig.time(17, 15))
        XCTAssertNil(rig.onBoard.departureAsk)
        XCTAssertFalse(rig.onBoard.asksDeparture)
        XCTAssertEqual(RideStripContent(rig.onBoard), .otherwise)

        try asking(rig, at: DepartureRig.time(17, 16, 10))
        XCTAssertEqual(rig.onBoard.departureAsk?.ride, DemoRide.ride(on: DepartureRig.day))
        XCTAssertTrue(rig.onBoard.asksDeparture)
        XCTAssertEqual(RideStripContent(rig.onBoard), .asking, "In detection's question card")

        try asking(rig, at: DepartureRig.time(17, 26))
        XCTAssertNil(rig.onBoard.departureAsk, "Gone with the window")
    }

    func testDetectionsQuestionWinsTheStrip() {
        XCTAssertEqual(RideStripContent(isRiding: false, detection: .idle, asksDeparture: true), .asking)
        XCTAssertEqual(RideStripContent(isRiding: true, detection: .idle, asksDeparture: true), .riding)
    }

    func testYesStartsTheRideWithSourceDeparture() async throws {
        let recorder = RecordingAnalytics.install()
        let rig = DepartureRig.started(at: DepartureRig.time(17, 16))
        try asking(rig, at: DepartureRig.time(17, 16, 10))

        let started = await rig.onBoard.acceptDeparture()

        XCTAssertTrue(started)
        XCTAssertNotNil(rig.onBoard.activeRide)
        XCTAssertNil(rig.onBoard.departureAsk)
        XCTAssertEqual(recorder.events, [
            .departureQuestionAnswered(yes: true, surface: .schedule),
            .rideStarted(source: .departure, demo: true),
        ])
        try asking(rig, at: DepartureRig.time(17, 17))
        XCTAssertNil(rig.onBoard.departureAsk, "Never while a ride runs")
    }

    func testNoIsKeptForTheDay() throws {
        let recorder = RecordingAnalytics.install()
        let rig = DepartureRig.started(at: DepartureRig.time(17, 16))
        try asking(rig, at: DepartureRig.time(17, 16, 10))

        rig.onBoard.declineDeparture()

        XCTAssertNil(rig.onBoard.departureAsk)
        XCTAssertEqual(recorder.events, [.departureQuestionAnswered(yes: false, surface: .schedule)])
        try asking(rig, at: DepartureRig.time(17, 17))
        XCTAssertNil(rig.onBoard.departureAsk, "Nothing asks about that train again")
    }

    /// A No on the card, the notification or Schedule's strip silences train detection for that trip today too.
    func testNoBlocksDetectionForThatTripToday() async throws {
        let recorder = RecordingAnalytics.install()
        let defaults = UserDefaults.ephemeral()
        let key = TripKey(serviceDay: DepartureRig.day, tripId: DemoRide.tripId)
        XCTAssertFalse(DepartureQuestion.isDeclined(key, in: defaults))

        DepartureQuestion.decline(key, in: defaults, surface: .card)

        XCTAssertTrue(DepartureQuestion.isDeclined(key, in: defaults))
        XCTAssertEqual(defaults.stringArray(forKey: TrainDetector.silencedKey), ["\(DepartureRig.day.dateKey)/\(DemoRide.tripId)"])
        XCTAssertEqual(recorder.events, [.departureQuestionAnswered(yes: false, surface: .card)])

        let onBoard = OnBoard(app: nil, declines: defaults)
        let session = DemoDeparture.Session(day: DepartureRig.day, clock: TestClock(now: DepartureRig.time(17, 17)))
        let live = try XCTUnwrap(session.departure(at: DepartureRig.time(17, 17)).flatMap { LiveDeparture($0, now: DepartureRig.time(17, 17)) })
        onBoard.updateDepartureAsk(live, route: DemoRide.route, isDemo: false)
        XCTAssertNil(onBoard.departureAsk, "Declined on the card: Schedule does not ask either")
    }

    func testTheDepartureQuestionIsNotAnAlertUpdate() {
        let userInfo: [AnyHashable: Any] = ["tripId": "20261109-LW-1256", "serviceDate": "20261109", "kind": "departure"]
        XCTAssertNil(AlertUpdate(id: "1", deliveredAt: Date(), title: "On the 7:13 AM train?", body: "", userInfo: userInfo))
        XCTAssertNotNil(NotificationLink(userInfo: userInfo), "A tap opens the train's Trip details")
    }

    func testTheNotificationsActions() {
        let category = DepartureNotice.notificationCategory
        XCTAssertEqual(category.identifier, "depart.question")
        XCTAssertEqual(category.actions.map(\.identifier), ["depart.yes", "depart.no"])
        XCTAssertEqual(category.actions.map(\.title), ["Yes", "No"])
        XCTAssertTrue(category.actions[0].options.contains(.foreground), "Yes opens the app, where the ride starts")
        XCTAssertFalse(category.actions[1].options.contains(.foreground), "No stays in the background")
    }
}
