import XCTest
@testable import TrainTimes

/// The wrong train warning's presenter (TT-250, D127): how it reaches the rider (in front, locked with a card, no card), the
/// answers, the expiry, the end of its ride, "I’m fine" kept for the day (the demo's in memory only), and its analytics.
@MainActor
final class WrongTrainTests: XCTestCase {
    private var recorder: RecordingAnalytics!
    private let ride = OnBoardFixtures.ride

    override func setUp() async throws {
        try await super.setUp()
        recorder = RecordingAnalytics.install()
    }

    override func tearDown() async throws {
        Analytics.tracker = nil
        try await super.tearDown()
    }

    private func events(_ name: String) -> [AnalyticsEvent] {
        recorder.events.filter { $0.name == name }
    }

    // MARK: How it shows

    func testInFrontAlarmPlaysOnceAndTheCardChangesWithNoAlert() async {
        let rig = WrongTrainRig()
        rig.active.isActive = true

        await rig.presenter.raise(WrongTrainFixtures.warning(), now: WrongTrainFixtures.now)?.value

        XCTAssertEqual(rig.haptics.played, [.alarm])
        XCTAssertEqual(rig.card.beats, [1], "One update")
        XCTAssertTrue(rig.card.alerts.isEmpty, "No alert: the app shows the warning")
        XCTAssertTrue(rig.notifier.posted.isEmpty)
        XCTAssertEqual(rig.presenter.warning, WrongTrainFixtures.warning())
        let warned = try? XCTUnwrap(events("wrong_train_warned").first)
        XCTAssertEqual(warned?.properties["shown"], .string("app"))
        XCTAssertEqual(warned?.properties["reason"], .string("skips_stop"))
        XCTAssertEqual(warned?.properties["evidence"], .string("feed"))
        XCTAssertEqual(warned?.properties["source"], .string("on_board"))
        XCTAssertEqual(warned?.properties["seconds_after"], .int(42))
        XCTAssertEqual(warned?.properties["demo"], .bool(false))
    }

    func testLockedWithACardItAlertsFiveTimesWithNoAlarm() async {
        let rig = WrongTrainRig()

        await rig.presenter.raise(WrongTrainFixtures.warning(), now: WrongTrainFixtures.now)?.value

        XCTAssertEqual(rig.card.beats, [1, 2, 3, 4, 5])
        XCTAssertEqual(rig.card.alerts.count, 5)
        XCTAssertEqual(rig.card.alerts.first?.title, "Wrong train?")
        XCTAssertEqual(rig.card.alerts.first?.body, "Doesn’t stop at Clarkson. Next stop Oakville, 11:38 AM.")
        XCTAssertTrue(rig.haptics.played.isEmpty, "The card buzzes, not the app")
        XCTAssertTrue(rig.notifier.posted.isEmpty)
        XCTAssertEqual(events("wrong_train_warned").first?.properties["shown"], .string("card"))
        let words = rig.card.calls.first?.wrong
        XCTAssertEqual(words?.reason, "Doesn’t stop at Clarkson")
        XCTAssertEqual(words?.stop, "Clarkson")
        XCTAssertEqual(words?.next, "Next stop Oakville · 11:38 AM")
        XCTAssertEqual(words?.nextStop, "Oakville")
    }

    func testLockedWithNoCardItPostsTheNotificationOnce() async {
        let rig = WrongTrainRig()
        rig.card.shows = false

        await rig.presenter.raise(WrongTrainFixtures.warning(), now: WrongTrainFixtures.now)?.value

        XCTAssertEqual(rig.card.calls.count, 1, "Tried once, no card")
        XCTAssertEqual(rig.notifier.posted.count, 1)
        let note = rig.notifier.posted.first
        XCTAssertEqual(note?.title, "Wrong train?")
        XCTAssertEqual(note?.body, "Doesn’t stop at Clarkson. Next stop Oakville, 11:38 AM.")
        XCTAssertEqual(note?.trainsTitle, "Trains from Oakville")
        XCTAssertEqual(note?.nextStopId, "OA")
        XCTAssertEqual(note?.originId, "UN")
        XCTAssertEqual(events("wrong_train_warned").first?.properties["shown"], .string("notification"))
    }

    func testWithNoTimeItNamesTheNextStation() {
        let warning = WrongTrainFixtures.warning(reason: .wrongWay, nextStopTime: nil)
        let formatter = TimeFormatter(format: .twelveHour)
        XCTAssertEqual(warning.reasonLine, "Going away from Clarkson")
        XCTAssertEqual(warning.nextLine(formatter: formatter), "Next station Oakville")
        XCTAssertEqual(warning.notificationBody(formatter: formatter), "Going away from Clarkson. Next station Oakville.")
    }

    func testRaisedTwiceItShowsOnce() async {
        let rig = WrongTrainRig()
        rig.active.isActive = true
        await rig.presenter.raise(WrongTrainFixtures.warning(), now: WrongTrainFixtures.now)?.value
        XCTAssertNil(rig.presenter.raise(WrongTrainFixtures.warning(), now: WrongTrainFixtures.now))
        XCTAssertEqual(rig.haptics.played, [.alarm])
        XCTAssertEqual(events("wrong_train_warned").count, 1)
    }

    func testATrainAnsweredFineTodayNeverShows() {
        let rig = WrongTrainRig()
        rig.store.storeFine(ride)
        XCTAssertNil(rig.presenter.raise(WrongTrainFixtures.warning(), now: WrongTrainFixtures.now))
        XCTAssertNil(rig.presenter.warning)
    }

    // MARK: I’m fine

    func testFineKeepsTheRideClearsTheCardAndRemembersTheTrain() async {
        let rig = WrongTrainRig()
        rig.active.isActive = true
        await rig.presenter.raise(WrongTrainFixtures.warning(), now: WrongTrainFixtures.now)?.value
        rig.clock.advance(seconds: 12)

        rig.presenter.fine(surface: .ride)
        await WrongTrainFixtures.settle()

        XCTAssertNil(rig.presenter.warning)
        XCTAssertTrue(rig.store.isFine(ride))
        XCTAssertNil(rig.card.calls.last?.wrong, "The card is the ride's own again")
        XCTAssertGreaterThan(rig.notifier.removed, 0)
        XCTAssertTrue(rig.ended.isEmpty, "The ride carries on")
        XCTAssertEqual(rig.haptics.played, [.alarm], "No buzz from the presenter: the screen plays Tap")
        let answered = events("wrong_train_answered").first
        XCTAssertEqual(answered?.properties["answer"], .string("fine"))
        XCTAssertEqual(answered?.properties["surface"], .string("ride"))
        XCTAssertEqual(answered?.properties["seconds"], .int(12))
        XCTAssertNil(rig.presenter.raise(WrongTrainFixtures.warning(), now: WrongTrainFixtures.now), "Not again today")
    }

    func testTheCardsPillInTheMiddleOfTheFiveClearsItAndStopsTheRest() async {
        let rig = WrongTrainRig(gap: .seconds(30))
        let showing = rig.presenter.raise(WrongTrainFixtures.warning(), now: WrongTrainFixtures.now)
        for _ in 0..<1000 where rig.card.beats.isEmpty { await Task.yield() }

        rig.presenter.fine(for: ride, surface: .card)
        await showing?.value
        await WrongTrainFixtures.settle()

        XCTAssertEqual(rig.card.beats, [1], "The four still to come never went")
        XCTAssertNil(rig.card.calls.last?.wrong)
        XCTAssertTrue(rig.store.isFine(ride))
        XCTAssertEqual(events("wrong_train_answered").first?.properties["surface"], .string("card"))
    }

    func testFineForWithNoWarningHeldStoresTheTrainAndCounts() {
        let rig = WrongTrainRig()
        rig.presenter.fine(for: ride, surface: .notification)
        XCTAssertTrue(rig.store.isFine(ride))
        let answered = events("wrong_train_answered").first
        XCTAssertEqual(answered?.properties["answer"], .string("fine"))
        XCTAssertEqual(answered?.properties["surface"], .string("notification"))
    }

    func testTheDemosTrainIsNeverStoredAndWarnsAgainOnTheNextDemoRide() async {
        let rig = WrongTrainRig()
        rig.active.isActive = true
        let demo = DemoRide.wrongTrainWarning(for: DemoRide.ride(on: DemoRideRig.day))
        await rig.presenter.raise(demo, now: WrongTrainFixtures.now)?.value
        rig.presenter.fine(surface: .schedule)

        XCTAssertFalse(rig.store.isFine(demo.ride), "Every demo ride of a day is the same Ride: never stored")
        XCTAssertNil(rig.presenter.raise(demo, now: WrongTrainFixtures.now), "Kept for that demo ride")

        let next = DemoRide.engine(on: DemoRideRig.day, clock: TestClock(now: DemoRideRig.time(17, 13)), tickInterval: nil)
        rig.presenter.followDemo(next)
        XCTAssertNotNil(rig.presenter.raise(demo, now: WrongTrainFixtures.now), "The next demo ride warns again")
        XCTAssertEqual(events("wrong_train_answered").first?.properties["demo"], .bool(true))
    }

    // MARK: Trains from …

    func testTrainsEndsTheRideAndAsksForTheWayBack() async {
        let rig = WrongTrainRig()
        rig.active.isActive = true
        await rig.presenter.raise(WrongTrainFixtures.warning(), now: WrongTrainFixtures.now)?.value

        rig.presenter.trains(surface: .schedule)

        XCTAssertNil(rig.presenter.warning)
        XCTAssertEqual(rig.ended, [ride])
        XCTAssertEqual(rig.presenter.routeRequest?.nextStopId, "OA")
        XCTAssertEqual(rig.presenter.routeRequest?.stopId, "CL")
        XCTAssertEqual(rig.presenter.routeRequest?.originId, "UN")
        XCTAssertGreaterThan(rig.notifier.removed, 0)
        XCTAssertEqual(recorder.names, ["wrong_train_warned", "wrong_train_answered"])
        XCTAssertEqual(events("wrong_train_answered").first?.properties["answer"], .string("trains"))
        XCTAssertEqual(events("wrong_train_answered").first?.properties["surface"], .string("schedule"))

        let request = try? XCTUnwrap(rig.presenter.routeRequest)
        if let request { rig.presenter.routeHandled(request) }
        XCTAssertNil(rig.presenter.routeRequest)
    }

    func testTrainsFromTheNotificationWithNoWarningHeldEndsTheAppsRide() async throws {
        let rig = WrongTrainRig(setsEndRide: false)
        let engine = RideEngine(
            data: FakeRideData(plan: try OnBoardFixtures.plan()), location: FakeLocation(authorized: true),
            clock: TestClock(now: WrongTrainFixtures.now), defaults: .ephemeral(), tickInterval: nil
        )
        let started = await engine.start(ride)
        XCTAssertTrue(started)
        rig.presenter.follow(engine)

        rig.presenter.trains(for: ride, nextStopId: "OA", originId: "UN", surface: .notification)

        XCTAssertEqual(engine.state?.endReason, .wrongTrain)
        XCTAssertEqual(rig.presenter.routeRequest?.nextStopId, "OA")
        XCTAssertEqual(rig.presenter.routeRequest?.stopId, "CL")
        XCTAssertEqual(rig.presenter.routeRequest?.originId, "UN")
        let answered = events("wrong_train_answered").first
        XCTAssertEqual(answered?.properties["answer"], .string("trains"))
        XCTAssertEqual(answered?.properties["surface"], .string("notification"))
    }

    /// The notification's "Trains from …" on a cold launch, before the restore: the ride saved on device is that train's,
    /// so it ends and the train is declined today.
    func testTrainsFromTheNotificationBeforeTheRestoreEndsThatTrainsSavedRide() {
        let rig = WrongTrainRig(setsEndRide: false)
        let defaults = UserDefaults.ephemeral()
        SavedRide(ride: ride, startedAt: WrongTrainFixtures.now, startSource: .onBoard).write(to: defaults, key: RideEngine.storageKey)
        let engine = RideEngine(
            data: FakeRideData(plan: nil), location: FakeLocation(authorized: true),
            clock: TestClock(now: WrongTrainFixtures.now), defaults: defaults, tickInterval: nil
        )
        rig.presenter.follow(engine)

        rig.presenter.trains(for: ride, nextStopId: "OA", originId: "UN", surface: .notification)

        XCTAssertNil(SavedRide.read(from: defaults, key: RideEngine.storageKey))
        XCTAssertTrue(DepartureQuestion.isDeclined(ride.tripKey, in: defaults))
        XCTAssertEqual(rig.presenter.routeRequest?.nextStopId, "OA")
    }

    /// The same before the restore when the saved ride is another train (a later ride than the warned one): it carries on;
    /// only the route is shown.
    func testTrainsFromTheNotificationLeavesAnotherTrainsSavedRide() {
        let rig = WrongTrainRig(setsEndRide: false)
        let defaults = UserDefaults.ephemeral()
        let other = Ride(trip: TripKey(serviceDay: OnBoardFixtures.friday, tripId: "20261127-LW-1115"), from: "UN", to: "CL")
        SavedRide(ride: other, startedAt: WrongTrainFixtures.now, startSource: .onBoard).write(to: defaults, key: RideEngine.storageKey)
        let engine = RideEngine(
            data: FakeRideData(plan: nil), location: FakeLocation(authorized: true),
            clock: TestClock(now: WrongTrainFixtures.now), defaults: defaults, tickInterval: nil
        )
        rig.presenter.follow(engine)

        rig.presenter.trains(for: ride, nextStopId: "OA", originId: "UN", surface: .notification)

        XCTAssertEqual(SavedRide.read(from: defaults, key: RideEngine.storageKey)?.ride, other)
        XCTAssertFalse(DepartureQuestion.isDeclined(other.tripKey, in: defaults))
        XCTAssertEqual(rig.presenter.routeRequest?.nextStopId, "OA")
    }

    // MARK: Endings

    func testUnansweredItEndsTheRideAtItsExpiryOnTheDemosRate() async throws {
        let rig = WrongTrainRig()
        rig.active.isActive = true
        // 6 s of the raising engine's clock at 60x: a tenth of a second.
        let warning = WrongTrainFixtures.warning(expires: WrongTrainFixtures.now.addingTimeInterval(6))
        await rig.presenter.raise(warning, now: WrongTrainFixtures.now, rate: 60)?.value

        for _ in 0..<300 where rig.presenter.warning != nil { try await Task.sleep(for: .milliseconds(10)) }

        XCTAssertNil(rig.presenter.warning)
        XCTAssertEqual(rig.ended, [ride])
        XCTAssertEqual(events("wrong_train_answered").first?.properties["answer"], .string("expired"))
        XCTAssertNil(events("wrong_train_answered").first?.properties["surface"])
    }

    func testWithdrawTakesItAwaySilently() async {
        let rig = WrongTrainRig()
        await rig.presenter.raise(WrongTrainFixtures.warning(), now: WrongTrainFixtures.now)?.value

        rig.presenter.withdraw()
        await WrongTrainFixtures.settle()

        XCTAssertNil(rig.presenter.warning)
        XCTAssertTrue(rig.ended.isEmpty, "The ride carries on")
        XCTAssertTrue(rig.haptics.played.isEmpty)
        XCTAssertNil(rig.card.calls.last?.wrong)
        XCTAssertEqual(events("wrong_train_answered").first?.properties["answer"], .string("withdrawn"))
    }

    func testAnAnswerInTheMiddleOfTheFiveStopsTheRest() async {
        let rig = WrongTrainRig(gap: .seconds(30))
        rig.presenter.keepAwake()
        let showing = rig.presenter.raise(WrongTrainFixtures.warning(), now: WrongTrainFixtures.now)
        for _ in 0..<1000 where rig.card.beats.isEmpty { await Task.yield() }

        rig.presenter.withdraw()
        await showing?.value

        XCTAssertEqual(rig.card.beats, [1])
        XCTAssertEqual(rig.background.begun, 1)
        XCTAssertEqual(rig.background.ended, 1, "No background time left taken")
    }

    func testEndRideWhileItShowsCountsAsEndRide() async {
        let rig = WrongTrainRig()
        rig.active.isActive = true
        await rig.presenter.raise(WrongTrainFixtures.warning(), now: WrongTrainFixtures.now)?.value

        rig.presenter.endedByRider(ride)

        XCTAssertNil(rig.presenter.warning)
        XCTAssertEqual(events("wrong_train_answered").first?.properties["answer"], .string("end_ride"))
    }

    func testTheRideArrivingTakesItsWarningAway() async throws {
        let rig = WrongTrainRig()
        rig.active.isActive = true
        let engine = RideEngine(
            data: FakeRideData(plan: try OnBoardFixtures.plan()), location: FakeLocation(authorized: true),
            clock: TestClock(now: WrongTrainFixtures.now), defaults: .ephemeral(), tickInterval: nil
        )
        rig.presenter.follow(engine)
        let started = await engine.start(ride)
        XCTAssertTrue(started)
        await rig.presenter.raise(WrongTrainFixtures.warning(), now: WrongTrainFixtures.now)?.value

        engine.end(.arrived)
        for _ in 0..<1000 where rig.presenter.warning != nil { await Task.yield() }

        XCTAssertNil(rig.presenter.warning)
        XCTAssertEqual(events("wrong_train_answered").first?.properties["answer"], .string("withdrawn"))
    }

    // MARK: The store

    func testFineIsForgottenTheNextDay() {
        let store = WrongTrainStore(defaults: .ephemeral())
        store.storeFine(ride)
        XCTAssertTrue(store.isFine(ride))

        let tomorrow = Ride(
            trip: TripKey(serviceDay: ServiceDay(year: 2026, month: 11, day: 28), tripId: ride.tripId), from: "UN", to: "CL"
        )
        XCTAssertFalse(store.isFine(tomorrow), "The same trip on another day")
        store.storeFine(tomorrow)
        XCTAssertFalse(store.isFine(ride), "Yesterday's answer is cleared with the day")
        XCTAssertTrue(store.isFine(tomorrow))
        XCTAssertFalse(WrongTrainStore(defaults: nil).isFine(ride))
    }
}
