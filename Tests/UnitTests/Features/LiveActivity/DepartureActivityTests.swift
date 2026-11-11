import XCTest
@testable import TrainTimes

/// TT-178: the alerted train's countdown as its Live Activity shows it (*Live-Depart-Lock*, the island cells), through the
/// demo departure's moments; the push payload the alert server sends; the activity's links; and the tokens the app reports.
@MainActor
final class DepartureActivityTests: XCTestCase {
    private let formatter = TimeFormatter(format: .twelveHour)
    /// The device clock, which the countdown runs on: a day away from the demo's clock, to show the two are kept apart.
    private let deviceNow = DepartureRig.time(17, 1).addingTimeInterval(86_400)

    private func content(at time: Date, hasPlatformSource: Bool = true) throws -> RideActivityAttributes.ContentState {
        let session = DemoDeparture.Session(day: DepartureRig.day, clock: TestClock(now: time))
        let departure = try XCTUnwrap(session.departure(at: time))
        let live = try XCTUnwrap(LiveDeparture(departure, now: time))
        return RideActivityAttributes.ContentState(
            departure: live, origin: session.route.from.name, destination: session.route.to.name,
            hasPlatformSource: hasPlatformSource, now: time, deviceNow: deviceNow, formatter: formatter
        )
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
        XCTAssertEqual(content.title, "5:13 PM to Clarkson")
        XCTAssertEqual(content.detail, "Platform · On time")
        XCTAssertEqual(content.platform, "Platform")
        XCTAssertTrue(content.pill, "The pill follows Platform while it is worth waiting for")
        XCTAssertFalse(content.late)
        XCTAssertEqual(try secondsLeft(content), 12 * 60, accuracy: 1, "On the device clock, to 5:13 on the demo's")
        XCTAssertEqual(content.time, "departs")
        XCTAssertEqual(content.now, "")
        XCTAssertEqual(content.departure, "Union 5:13 PM")
        XCTAssertEqual(content.arrival, "Clarkson 5:43 PM")
        XCTAssertEqual(content.arrives, "Arrives Clarkson 5:43 PM")
        XCTAssertEqual(content.position, 0)
        XCTAssertEqual(content.button, "I’m on board")
        XCTAssertEqual(content.updated, "Updated 5:01 PM")
    }

    func testWithoutAPlatformFeedItSaysCheckTheBoard() throws {
        let content = try content(at: DepartureRig.time(17, 1), hasPlatformSource: false)
        XCTAssertEqual(content.detail, "Check the board · On time", "What the alert server's activity says too (GO posts no platforms)")
        XCTAssertEqual(content.platform, "Check the board")
        XCTAssertFalse(content.pill)
    }

    func testThePostedPlatformReplacesThePill() throws {
        let content = try content(at: DepartureRig.time(17, 3, 30))
        XCTAssertEqual(content.detail, "Platform 7 · On time")
        XCTAssertEqual(content.platform, "Platform 7")
        XCTAssertFalse(content.pill)
    }

    func testALateTrainCountsDownToItsExpectedDepartureInAmber() throws {
        let content = try content(at: DepartureRig.time(17, 5))
        XCTAssertEqual(content.phase, .countingDown)
        XCTAssertEqual(content.title, "5:13 PM to Clarkson", "The scheduled time stays the train's name (D9)")
        XCTAssertEqual(content.detail, "Platform 7 · Delayed 3 min")
        XCTAssertTrue(content.late)
        XCTAssertEqual(try secondsLeft(content), 11 * 60, accuracy: 1, "To 5:16")
        XCTAssertEqual(content.departure, "Union 5:16 PM")
        XCTAssertEqual(content.arrival, "Clarkson 5:46 PM")
    }

    func testBoardingNowInTheLastTwoMinutes() throws {
        let content = try content(at: DepartureRig.time(17, 14, 30))
        XCTAssertEqual(content.phase, .boarding)
        XCTAssertEqual(content.detail, "Platform 7 · Boarding now")
        XCTAssertFalse(content.late, "Boarding is green, not amber")
        XCTAssertEqual(try secondsLeft(content), 90, accuracy: 1)
    }

    func testDepartedDropsTheCountdown() throws {
        let content = try content(at: DepartureRig.time(17, 16, 30))
        XCTAssertEqual(content.phase, .departed)
        XCTAssertEqual(content.detail, "Platform 7 · Departed 5:16 PM")
        XCTAssertNil(content.countdownEnd)
        XCTAssertEqual(content.time, "")
        XCTAssertFalse(content.late)
    }

    func testTwentyFourHourTimes() throws {
        let session = DemoDeparture.Session(day: DepartureRig.day, clock: TestClock(now: DepartureRig.time(17, 1)))
        let time = DepartureRig.time(17, 1)
        let live = try XCTUnwrap(session.departure(at: time).flatMap { LiveDeparture($0, now: time) })
        let content = RideActivityAttributes.ContentState(
            departure: live, origin: session.route.from.name, destination: session.route.to.name, hasPlatformSource: true,
            now: time, deviceNow: deviceNow, formatter: TimeFormatter(format: .twentyFourHour)
        )
        XCTAssertEqual(content.title, "17:13 to Clarkson")
        XCTAssertEqual(content.departure, "Union 17:13")
    }

    func testTheActivityEndsTwoMinutesAfterTheTrainLeftOnTheDeviceClock() throws {
        let time = DepartureRig.time(17, 5)
        let session = DemoDeparture.Session(day: DepartureRig.day, clock: TestClock(now: time))
        let live = try XCTUnwrap(session.departure(at: time).flatMap { LiveDeparture($0, now: time) })
        let stale = RideLiveActivity.departureStaleDate(live, now: time, deviceNow: deviceNow)
        XCTAssertEqual(stale.timeIntervalSince(deviceNow), 13 * 60, accuracy: 1, "5:16 PM plus 2 min, 13 min from 5:05")
    }

    func testAnUpdateOnlyWhenWhatItShowsChanges() throws {
        let departure = try content(at: DepartureRig.time(17, 5))
        XCTAssertTrue(RideLiveActivity.needsUpdate(from: departure, to: departure, sentAt: nil, now: deviceNow))
        XCTAssertFalse(RideLiveActivity.needsUpdate(from: departure, to: departure, sentAt: deviceNow, now: deviceNow))
        let later = try content(at: DepartureRig.time(17, 5, 5))
        XCTAssertFalse(
            RideLiveActivity.needsUpdate(from: departure, to: later, sentAt: deviceNow, now: deviceNow.addingTimeInterval(5)),
            "The same countdown 5 s on sends nothing"
        )
        let boarding = try content(at: DepartureRig.time(17, 14))
        XCTAssertTrue(RideLiveActivity.needsUpdate(from: departure, to: boarding, sentAt: deviceNow, now: deviceNow))
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
        {"phase":"countingDown","title":"7:13 AM to Union","detail":"Check the board · On time","now":"","time":"departs",
         "departure":"Oakville 7:13 AM","arrival":"Union 7:47 AM","arrives":"Arrives Union 7:47 AM","position":0,
         "button":"I’m on board","updated":"Updated 6:43 AM","platform":"Check the board","pill":false,"late":false,
         "countdownEnd":1762427580}
        """
        let state = try JSONDecoder().decode(RideActivityAttributes.ContentState.self, from: Data(json.utf8))
        XCTAssertEqual(state.phase, .countingDown)
        XCTAssertTrue(state.isDeparture)
        XCTAssertEqual(state.title, "7:13 AM to Union")
        XCTAssertEqual(state.detail, "Check the board · On time")
        XCTAssertEqual(state.countdownEnd, Date(timeIntervalSince1970: 1_762_427_580))
        XCTAssertEqual(state.arrives, "Arrives Union 7:47 AM")
        XCTAssertEqual(state.platform, "Check the board")
        XCTAssertFalse(state.pill)

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
        await rules.report(report)
        let none = await server.activityReports
        XCTAssertEqual(none, [])

        await rules.save(AlertRule(kind: .thisTrip, trip: AlertFixtures.trip(), route: AlertFixtures.route))
        await server.answerUnknownInstallationOnce()
        await rules.report(report)
        let reports = await server.activityReports
        XCTAssertEqual(reports, [report])
        let registrations = await server.registrations
        XCTAssertEqual(registrations.count, 2, "Registered with the save, then again for the unknown installation")
    }
}
