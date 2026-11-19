import XCTest
@testable import TrainTimes

/// TT-178, TT-205: the alerted train's countdown as its Live Activity's one card shows it (boards 3 and 13), through the
/// demo departure's moments; the push payload the alert server sends; the activity's links; the tokens the app reports;
/// and when a card ends with its alert (TT-240).
@MainActor
final class DepartureActivityTests: XCTestCase {
    private let formatter = TimeFormatter(format: .twelveHour)
    /// The device clock, which the countdown runs on: a day away from the demo's clock, to show the two are kept apart.
    private let deviceNow = DepartureRig.time(17, 1).addingTimeInterval(86_400)

    private func content(
        at time: Date, formatter: TimeFormatter = TimeFormatter(format: .twelveHour)
    ) throws -> RideActivityAttributes.ContentState {
        let session = DemoDeparture.Session(day: DepartureRig.day, clock: TestClock(now: time))
        let departure = try XCTUnwrap(session.departure(at: time))
        let live = try XCTUnwrap(LiveDeparture(departure, now: time))
        return RideActivityAttributes.ContentState(departure: live, now: time, deviceNow: deviceNow, formatter: formatter)
    }

    private func secondsLeft(_ content: RideActivityAttributes.ContentState) throws -> TimeInterval {
        try XCTUnwrap(content.countdownEnd).timeIntervalSince(deviceNow)
    }

    // MARK: The demo departure's moments

    func testCountingDownWithThePlatformPending() throws {
        let content = try content(at: DepartureRig.time(17, 1))
        XCTAssertEqual(content.phase, .countingDown)
        XCTAssertTrue(content.isDeparture)
        XCTAssertFalse(content.isAlert)
        XCTAssertFalse(content.isGreen)
        XCTAssertEqual(content.title, "5:13 PM departs in")
        XCTAssertEqual(content.label, "Platform")
        XCTAssertNil(content.platformNumber, "The dash pill while it is not posted")
        XCTAssertNil(content.value)
        XCTAssertNil(content.delay)
        XCTAssertFalse(content.late)
        XCTAssertFalse(content.isClose)
        XCTAssertEqual(try secondsLeft(content), 12 * 60, accuracy: 1, "On the device clock, to 5:13 on the demo's")
        XCTAssertEqual(content.minutes, "12 min", "Whole minutes, no seconds (TT-219)")
        XCTAssertEqual(content.now, "")
        XCTAssertEqual(content.position, 0)
        XCTAssertEqual(content.updated, "Updated 5:01 PM")
    }

    func testThePostedPlatformGoesInThePill() throws {
        let content = try content(at: DepartureRig.time(17, 3, 30))
        XCTAssertEqual(content.label, "Platform")
        XCTAssertEqual(content.platformNumber, "7")
    }

    func testALateTrainCountsDownToItsExpectedDepartureAndShowsThatTime() throws {
        let content = try content(at: DepartureRig.time(17, 5))
        XCTAssertEqual(content.phase, .countingDown)
        XCTAssertEqual(content.title, "5:16 PM departs in", "The expected time, in amber")
        XCTAssertEqual(content.delay, "3 min late")
        XCTAssertTrue(content.late)
        XCTAssertEqual(try secondsLeft(content), 11 * 60, accuracy: 1, "To 5:16")
        XCTAssertEqual(content.minutes, "11 min")
    }

    func testBoardingNowInTheLastTwoMinutes() throws {
        let content = try content(at: DepartureRig.time(17, 14, 30))
        XCTAssertEqual(content.phase, .boarding)
        XCTAssertEqual(content.title, "5:16 PM boarding now")
        XCTAssertTrue(content.isClose, "The number turns mint")
        XCTAssertEqual(try secondsLeft(content), 90, accuracy: 1)
        XCTAssertEqual(content.minutes, "1 min")
    }

    func testOnceItHasLeftTheCardAsksAndDropsTheCountdown() throws {
        let content = try content(at: DepartureRig.time(17, 16, 30))
        XCTAssertEqual(content.phase, .departed)
        XCTAssertTrue(content.isAsking, "TT-231: On board? in the Departed card's place")
        XCTAssertEqual(content.title, "5:16 PM departed")
        XCTAssertNil(content.countdownEnd)
        XCTAssertNil(content.minutes)
        XCTAssertNil(content.delay)
        XCTAssertFalse(content.late)
    }

    func testTwentyFourHourTimes() throws {
        let content = try content(at: DepartureRig.time(17, 1), formatter: TimeFormatter(format: .twentyFourHour))
        XCTAssertEqual(content.title, "17:13 departs in")
    }

    func testTheActivityEndsTenMinutesAfterTheTrainLeftOnTheDeviceClock() throws {
        let time = DepartureRig.time(17, 5)
        let session = DemoDeparture.Session(day: DepartureRig.day, clock: TestClock(now: time))
        let live = try XCTUnwrap(session.departure(at: time).flatMap { LiveDeparture($0, now: time) })
        let stale = RideLiveActivity.departureStaleDate(live, now: time, deviceNow: deviceNow)
        XCTAssertEqual(stale.timeIntervalSince(deviceNow), 21 * 60, accuracy: 1, "5:16 PM plus 10 min (TT-231), 21 min from 5:05")
    }

    func testAnUpdateOnlyWhenWhatItShowsChanges() throws {
        let departure = try content(at: DepartureRig.time(17, 5))
        XCTAssertTrue(RideLiveActivity.needsUpdate(from: departure, to: departure, sentAt: nil, now: deviceNow))
        XCTAssertFalse(RideLiveActivity.needsUpdate(from: departure, to: departure, sentAt: deviceNow, now: deviceNow))
        let shown = try content(at: DepartureRig.time(17, 5, 10))
        let later = try content(at: DepartureRig.time(17, 5, 15))
        XCTAssertFalse(
            RideLiveActivity.needsUpdate(from: shown, to: later, sentAt: deviceNow, now: deviceNow.addingTimeInterval(5)),
            "The same minute 5 s on sends nothing"
        )
        XCTAssertTrue(
            RideLiveActivity.needsUpdate(from: departure, to: shown, sentAt: deviceNow, now: deviceNow.addingTimeInterval(10)),
            "A new minute, 11 min to 10 min, is sent (TT-219)"
        )
        let boarding = try content(at: DepartureRig.time(17, 14))
        XCTAssertTrue(RideLiveActivity.needsUpdate(from: departure, to: boarding, sentAt: deviceNow, now: deviceNow))
    }

    // MARK: Boarding at the platform (TT-233, D114)

    /// The 5:13 PM train, on time, Platform 7 posted, where GO's train feed places it: `metres` from the rider's station,
    /// seen at `seen`. With no `metres` the feed does not place it, and it follows the clock.
    private func train(metres: Double? = nil, seen: Date = DepartureRig.time(17, 0)) -> Departure {
        let leaves = DepartureRig.time(17, 13)
        return Departure(
            trip: Trip(
                key: TripKey(serviceDay: DepartureRig.day, tripId: "LW-1713"), scheduledDeparture: leaves,
                scheduledArrival: leaves.addingTimeInterval(30 * 60), platform: .published("7"), tags: []
            ),
            status: .onTime,
            expectedDeparture: leaves,
            expectedArrival: leaves.addingTimeInterval(30 * 60),
            originFix: metres.map { OriginFix(metres: $0, reportedAt: seen) }
        )
    }

    private func content(of train: Departure, at time: Date) throws -> RideActivityAttributes.ContentState {
        let live = try XCTUnwrap(LiveDeparture(train, now: time))
        return RideActivityAttributes.ContentState(departure: live, now: time, deviceNow: deviceNow, formatter: formatter)
    }

    private func asksSilently(_ train: Departure, at time: Date) throws -> Bool {
        let live = try XCTUnwrap(LiveDeparture(train, now: time))
        return RideLiveActivity.asksSilently(live, now: time)
    }

    func testATrainAtItsPlatformIsBoardingNowLongBeforeItsTime() throws {
        let content = try content(of: train(metres: 150, seen: DepartureRig.time(16, 58)), at: DepartureRig.time(16, 58, 10))
        XCTAssertEqual(content.phase, .boarding, "15 min before, standing at its platform")
        XCTAssertEqual(content.title, "5:13 PM boarding now")
        XCTAssertEqual(content.minutes, "14 min", "Still the minutes to its time")
        XCTAssertTrue(content.isClose, "Mint: the number, the line's words and the platform's number")
        XCTAssertEqual(content.label, "Platform")
        XCTAssertEqual(content.platformNumber, "7")
        XCTAssertFalse(content.asks)
        XCTAssertEqual(try secondsLeft(content), 14 * 60 + 50, accuracy: 1)
    }

    func testPastItsTimeAndStillAtThePlatformTheMinutesGiveWayToDeparting() throws {
        let lastMinute = try content(of: train(metres: 150, seen: DepartureRig.time(17, 12, 20)), at: DepartureRig.time(17, 12, 30))
        XCTAssertEqual(lastMinute.minutes, "1 min", "Its time has not come")

        let departing = try content(of: train(metres: 150, seen: DepartureRig.time(17, 14)), at: DepartureRig.time(17, 14, 10))
        XCTAssertEqual(departing.phase, .boarding, "No Departed until it moves")
        XCTAssertEqual(departing.title, "5:13 PM boarding now")
        XCTAssertEqual(departing.minutes, "Departing", "Never \"1 min\" for a train past its time")
        XCTAssertTrue(departing.isClose)
        XCTAssertFalse(departing.asks)
        XCTAssertEqual(departing.label, "Platform")
        XCTAssertEqual(departing.platformNumber, "7")
        XCTAssertEqual(try secondsLeft(departing), -70, accuracy: 1, "The countdown's end is kept: its time, now past")

        // The word is a change the rider sees, so the card is sent again; then nothing until it moves.
        var shown = departing
        shown.minutes = "1 min"
        XCTAssertTrue(RideLiveActivity.needsUpdate(from: shown, to: departing, sentAt: deviceNow, now: deviceNow))
        XCTAssertFalse(RideLiveActivity.needsUpdate(from: departing, to: departing, sentAt: deviceNow, now: deviceNow))
    }

    func testOnceItMovesOffTheCardAsks() throws {
        let content = try content(of: train(metres: 800, seen: DepartureRig.time(17, 14, 30)), at: DepartureRig.time(17, 14, 40))
        XCTAssertEqual(content.phase, .departed)
        XCTAssertTrue(content.isAsking, "TT-231's question, at the moment the train moves")
        XCTAssertEqual(content.title, "5:13 PM departed")
        XCTAssertNil(content.minutes)
        XCTAssertNil(content.countdownEnd)
        XCTAssertNil(content.platformNumber)
        XCTAssertFalse(content.isClose)
    }

    func testOnTheClockTheWordDepartingNeverShows() throws {
        let boarding = try content(of: train(), at: DepartureRig.time(17, 12, 59))
        XCTAssertEqual(boarding.phase, .boarding, "No position: the last 2 min, as before")
        XCTAssertEqual(boarding.minutes, "1 min")
        let left = try content(of: train(), at: DepartureRig.time(17, 13))
        XCTAssertEqual(left.phase, .departed, "And it has left at its time")
        XCTAssertNil(left.minutes)
    }

    func testTheServerIsToldToAskSilentlyOnTheClockOrOnceAPlacedTrainHasLeft() throws {
        // No position: 75 s before its time, as before TT-233.
        XCTAssertFalse(try asksSilently(train(), at: DepartureRig.time(17, 11, 44)))
        XCTAssertTrue(try asksSilently(train(), at: DepartureRig.time(17, 11, 45)))
        XCTAssertTrue(try asksSilently(train(), at: DepartureRig.time(17, 13, 30)), "It has left, by the clock")
        // At its platform nothing is told ahead: it leaves when it moves, not at its time.
        XCTAssertFalse(try asksSilently(train(metres: 150, seen: DepartureRig.time(17, 12)), at: DepartureRig.time(17, 12, 30)))
        XCTAssertFalse(
            try asksSilently(train(metres: 150, seen: DepartureRig.time(17, 15)), at: DepartureRig.time(17, 15, 10)),
            "Still boarding 2 min past its time"
        )
        XCTAssertTrue(
            try asksSilently(train(metres: 800, seen: DepartureRig.time(17, 15, 20)), at: DepartureRig.time(17, 15, 30)),
            "It moved off"
        )
    }

    // MARK: The push payload

    func testTheStateRoundTripsWithItsCountdownAsSecondsSince1970() throws {
        let content = try content(at: DepartureRig.time(17, 5))
        let data = try JSONEncoder().encode(content)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["countdownEnd"] as? Double, content.countdownEnd?.timeIntervalSince1970)
        XCTAssertEqual(json["phase"] as? String, "countingDown")
        XCTAssertEqual(json["late"] as? Bool, true)
        let decoded = try JSONDecoder().decode(RideActivityAttributes.ContentState.self, from: data)
        XCTAssertEqual(decoded, content)
    }

    /// The `content-state` of the alert server's start (server/test/activity.test.ts, the 7:13 AM Oakville to Union train).
    func testTheAlertServersStateDecodes() throws {
        let json = """
        {"phase":"countingDown","title":"7:13 AM departs in","now":"","label":"Platform","late":false,"position":0,
         "isClose":false,"updated":"Updated 6:43 AM","countdownEnd":1762427580,"minutes":"30 min"}
        """
        let state = try JSONDecoder().decode(RideActivityAttributes.ContentState.self, from: Data(json.utf8))
        XCTAssertEqual(state.phase, .countingDown)
        XCTAssertTrue(state.isDeparture)
        XCTAssertEqual(state.title, "7:13 AM departs in")
        XCTAssertEqual(state.countdownEnd, Date(timeIntervalSince1970: 1_762_427_580))
        XCTAssertEqual(state.minutes, "30 min")
        XCTAssertEqual(state.label, "Platform")
        XCTAssertNil(state.platformNumber, "The server knows no platforms: the dash")
        XCTAssertNil(state.delay)

        let departed = try JSONDecoder().decode(RideActivityAttributes.ContentState.self, from: Data(#"{"phase":"departed"}"#.utf8))
        XCTAssertEqual(departed.phase, .departed)
        XCTAssertNil(departed.countdownEnd, "A missing key reads as empty rather than failing the activity")
        XCTAssertEqual(departed.title, "")
        XCTAssertFalse(departed.late)

        let attributes = """
        {"tripId":"20261106-LW-1256","serviceDate":20261106,"originId":"OA","destinationId":"UN","lineCode":"LW",
         "lineColorHex":"#8B1A31","destinationName":"Union","stopCount":3}
        """
        let decoded = try JSONDecoder().decode(RideActivityAttributes.self, from: Data(attributes.utf8))
        XCTAssertEqual(decoded.stopCount, 3)
        XCTAssertEqual(decoded.lineColorHex, "#8B1A31")
        let ride = Ride(decoded)
        XCTAssertEqual(ride.tripId, "20261106-LW-1256")
        XCTAssertEqual(ride.serviceDate, 20_261_106)
        XCTAssertEqual(ride.originId, "OA")
        XCTAssertEqual(ride.destinationId, "UN")
        XCTAssertTrue(decoded.shows(ride))
    }

    func testTheRideKeepsTheDeparturesStopCountSoTheHandOffKeepsTheActivity() {
        let day = DepartureRig.day
        let ride = DemoRide.ride(on: day)
        let attributes = RideActivityAttributes(ride: ride, plan: DemoRide.plan(on: day), line: DemoRide.line)
        XCTAssertEqual(attributes.stopCount, DemoRide.plan(on: day).stops.count)
        XCTAssertTrue(attributes.shows(Ride(attributes)))
        XCTAssertEqual(
            LiveActivityReport(attributes, handedOff: true),
            LiveActivityReport(
                tripId: DemoRide.tripId, serviceDate: String(day.dateKey), originId: "UN", destinationId: "CL", handedOff: true
            )
        )
    }

    // MARK: Links

    func testTheDepartureLinks() throws {
        XCTAssertEqual(RideActivityLink.departure.url.absoluteString, "traintimes://departure")
        XCTAssertEqual(RideActivityLink.board.url.absoluteString, "traintimes://departure/board")
        for link in [RideActivityLink.open, .end, .departure, .board] {
            XCTAssertEqual(RideActivityLink(link.url), link)
        }
        XCTAssertNil(RideActivityLink(try XCTUnwrap(URL(string: "traintimes://departure/other"))))
        XCTAssertNil(RideActivityLink(try XCTUnwrap(URL(string: "https://departure/board"))))
    }

    // MARK: Tokens

    func testTokensAreHex() {
        XCTAssertEqual(RideLiveActivity.hex(Data([0x0a, 0xff, 0x00, 0x42])), "0aff0042")
    }

    func testTheStartTokenGoesWithTheRegistrationOnceTheRiderHasAnAlert() async {
        let server = FakeAlertServer()
        let rules = AlertFixtures.rules(server)
        await rules.reportStartToken("ab12")
        let before = await server.registrations
        XCTAssertEqual(before, [], "No alert yet: only alerted trains go live")

        await rules.save(AlertRule(kind: .thisTrip, trip: AlertFixtures.trip(), route: AlertFixtures.route))
        await rules.reportStartToken("ab12")
        await rules.reportStartToken("cd34")
        let registrations = await server.registrations
        XCTAssertEqual(registrations.map(\.startToken), ["ab12", "cd34"], "A new token registers again; the same one does not")
    }

    func testActivityReportsNeedAnAlertAndReRegisterAnUnknownInstallation() async {
        let server = FakeAlertServer()
        let rules = AlertFixtures.rules(server)
        let report = LiveActivityReport(tripId: "LW-1713", serviceDate: "20261127", originId: "UN", destinationId: "CL", token: "ef")
        let needsNothing = await rules.report(report)
        XCTAssertTrue(needsNothing, "No alert: the server watches no train")
        let none = await server.activityReports
        XCTAssertEqual(none, [])

        await rules.save(AlertRule(kind: .thisTrip, trip: AlertFixtures.trip(), route: AlertFixtures.route))
        await server.answerUnknownInstallationOnce()
        let sent = await rules.report(report)
        XCTAssertTrue(sent)
        let reports = await server.activityReports
        XCTAssertEqual(reports, [report])
        let registrations = await server.registrations
        XCTAssertEqual(registrations.count, 2, "Registered with the save, then again for the unknown installation")

        await server.setFailing(true)
        let failed = await rules.report(report)
        XCTAssertFalse(failed, "An unreachable server: the hand-off is sent again")
    }

    // MARK: A card ends with its alert (TT-240, D118)

    /// The card of a fixture train: Oakville to Union, the 7:32 AM on Thu Nov 5 unless another is given.
    private func cardRide(_ trip: Trip = AlertFixtures.trip(), from: String = "OA", to: String = "UN") -> Ride {
        Ride(trip: trip.key, from: from, to: to)
    }

    func testACardStaysWhileItIsTheSourcesTrainOrAnAlertStandsBehindIt() {
        let card = cardRide()
        let other = cardRide(AlertFixtures.trip("LW-0802-20261105", departure: "13:02"))
        XCTAssertTrue(
            RideLiveActivity.keepsDeparture(card, source: nil, hasAlert: true),
            "No source (another day picked, a turned route, Schedule still loading) never ends a card whose alert is on"
        )
        XCTAssertTrue(RideLiveActivity.keepsDeparture(card, source: other, hasAlert: true), "Another alerted train is the source")
        XCTAssertFalse(RideLiveActivity.keepsDeparture(card, source: nil, hasAlert: false), "Its alert was removed or switched off")
        XCTAssertFalse(RideLiveActivity.keepsDeparture(card, source: other, hasAlert: false), "No card stays beside the source's")
        XCTAssertTrue(RideLiveActivity.keepsDeparture(card, source: card, hasAlert: false), "The demo departure has no alert")
        XCTAssertTrue(RideLiveActivity.keepsDeparture(card, source: nil, hasAlert: nil), "Before the rules are connected nothing ends")
    }

    func testAnAlertStandsBehindACardWhileItIsSwitchedOnForThatTrain() async {
        let server = FakeAlertServer()
        let rules = AlertFixtures.rules(server)
        let trip = AlertFixtures.trip()
        XCTAssertFalse(rules.hasAlert(for: cardRide(trip)), "No alert")

        var alert = AlertRule(kind: .thisTrip, trip: trip, route: AlertFixtures.route)
        await rules.save(alert)
        XCTAssertTrue(rules.hasAlert(for: cardRide(trip)))
        XCTAssertFalse(rules.hasAlert(for: cardRide(AlertFixtures.trip("LW-0802-20261105", departure: "13:02"))), "Another train")
        XCTAssertFalse(rules.hasAlert(for: cardRide(trip, from: "UN", to: "OA")), "The other way")
        XCTAssertFalse(rules.hasAlert(for: cardRide(AlertFixtures.trip(day: 6))), "The same trip id on another day")

        alert.paused = true
        await rules.save(alert)
        XCTAssertFalse(rules.hasAlert(for: cardRide(trip)), "Switched off")
        alert.paused = false
        await rules.save(alert)
        XCTAssertTrue(rules.hasAlert(for: cardRide(trip)), "Switched on again")
        await rules.delete(alert.id)
        XCTAssertFalse(rules.hasAlert(for: cardRide(trip)), "Removed")

        await server.setFailing(true)
        await rules.save(alert)
        XCTAssertTrue(rules.hasAlert(for: cardRide(trip)), "Switched on but not saved still counts, as the bell counts it")
    }

    func testARepeatAlertStandsBehindACardOnItsDaysBetweenItsStations() async {
        let server = FakeAlertServer()
        let rules = AlertFixtures.rules(server)
        let thursday = AlertFixtures.trip()
        var alert = AlertRule(kind: .repeating, trip: thursday, route: AlertFixtures.route, weekdays: [1, 2, 3, 4, 5])
        await rules.save(alert)
        XCTAssertTrue(rules.hasAlert(for: cardRide(thursday)))
        XCTAssertTrue(
            rules.hasAlert(for: cardRide(AlertFixtures.trip("LW-0732-20261106", day: 6))),
            "Friday's card names Friday's trip: the alert server starts it for the usual train"
        )
        XCTAssertFalse(rules.hasAlert(for: cardRide(AlertFixtures.trip("LW-0732-20261107", day: 7))), "Saturday is not one of its days")
        XCTAssertFalse(rules.hasAlert(for: cardRide(thursday, from: "UN", to: "OA")), "The other way")
        XCTAssertTrue(
            rules.hasAlert(for: cardRide(AlertFixtures.trip("LW-0802-20261105", departure: "13:02"))),
            "A card carries no scheduled time: on the alert's day between its stations it is kept, and the server ends the rest"
        )

        alert.weekdays = [1, 2, 3, 5]
        await rules.save(alert)
        XCTAssertFalse(rules.hasAlert(for: cardRide(thursday)), "Thursday taken out in the day panel")
        alert.weekdays = [1, 2, 3, 4, 5]
        alert.paused = true
        await rules.save(alert)
        XCTAssertFalse(rules.hasAlert(for: cardRide(thursday)), "The bell turned off keeps the days and pauses the alert")
    }

    func testAHandOffIsReportedWithNoAlertLeftAndNeverRegistersForIt() async {
        let server = FakeAlertServer()
        let rules = AlertFixtures.rules(server)
        let handOff = LiveActivityReport(tripId: "LW-1713", serviceDate: "20261127", originId: "UN", destinationId: "CL", handedOff: true)
        let sent = await rules.report(handOff)
        XCTAssertTrue(sent)
        let reports = await server.activityReports
        XCTAssertEqual(reports, [handOff], "The server ends a card whose alert is gone, and this one is the ride now")
        let registrations = await server.registrations
        XCTAssertEqual(registrations, [], "Nothing is registered for it")

        await server.answerUnknownInstallationOnce()
        let unknown = await rules.report(handOff)
        XCTAssertTrue(unknown, "An installation the server does not know has no card there to end")
        let stillNone = await server.registrations
        XCTAssertEqual(stillNone, [])

        await server.setFailing(true)
        let failed = await rules.report(handOff)
        XCTAssertFalse(failed, "An unreachable server: the hand-off is sent again")
    }

    func testARemovedCardIsReportedWithNoAlertLeft() async {
        let server = FakeAlertServer()
        let rules = AlertFixtures.rules(server)
        let removed = LiveActivityReport(tripId: "LW-1256", serviceDate: "20261105", originId: "OA", destinationId: "UN", removed: true)
        let sent = await rules.report(removed)
        XCTAssertTrue(sent)
        let reports = await server.activityReports
        XCTAssertEqual(reports, [removed], "The server follows the ended card no more, and starts a fresh one after Undo")
        let registrations = await server.registrations
        XCTAssertEqual(registrations, [], "Nothing is registered for it")

        let token = LiveActivityReport(tripId: "LW-1256", serviceDate: "20261105", originId: "OA", destinationId: "UN", token: "ab")
        let needless = await rules.report(token)
        XCTAssertTrue(needless)
        let still = await server.activityReports
        XCTAssertEqual(still, [removed], "Anything else needs no server with no alert left")
    }
}
