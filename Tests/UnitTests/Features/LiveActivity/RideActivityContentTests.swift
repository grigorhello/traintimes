import XCTest
@testable import TrainTimes

/// TT-174, TT-205: the ride as its Live Activity's one card shows it, through the demo ride's moments (boards 12, 13 and 15),
/// its size, and the rules that update, alert and end it.
@MainActor
final class RideActivityContentTests: XCTestCase {
    private let formatter = TimeFormatter(format: .twelveHour)
    /// The device clock, which the countdown runs on: a day away from the demo's clock, to show the two are kept apart.
    private let deviceNow = DemoRideRig.time(17, 32).addingTimeInterval(86_400)

    private func t(_ hours: Int, _ minutes: Int, _ seconds: Int = 0) -> Date {
        DemoRideRig.time(hours, minutes, seconds)
    }

    private func content(_ rig: DemoRideRig) throws -> RideActivityAttributes.ContentState {
        let engine = try XCTUnwrap(rig.engine)
        let state = try XCTUnwrap(engine.state)
        return try XCTUnwrap(
            RideActivityAttributes.ContentState(plan: rig.plan, state: state, now: engine.now, deviceNow: deviceNow, formatter: formatter)
        )
    }

    private func secondsLeft(_ content: RideActivityAttributes.ContentState) throws -> TimeInterval {
        try XCTUnwrap(content.countdownEnd).timeIntervalSince(deviceNow)
    }

    // MARK: The demo ride's moments

    func testTheAttributesNameTheRideTheLineAndYourStop() async throws {
        let rig = await DemoRideRig.started()
        let ride = DemoRide.ride(on: DemoRideRig.day)
        let attributes = RideActivityAttributes(ride: ride, plan: rig.plan, line: DemoRide.line)
        XCTAssertEqual(attributes.lineCode, "LW")
        XCTAssertEqual(attributes.lineColorHex, GOLineColor.hex["LW"])
        XCTAssertNotNil(attributes.lineColorHex)
        XCTAssertEqual(attributes.destinationName, "Clarkson")
        XCTAssertEqual(attributes.stopCount, 6)
        XCTAssertTrue(attributes.shows(ride))
        XCTAssertFalse(attributes.shows(nil))
        let other = Ride(trip: ride.tripKey, from: ride.originId, to: "PO")
        XCTAssertFalse(attributes.shows(other), "Another ride on the same train is another activity")

        let unknown = RideActivityAttributes(ride: ride, plan: rig.plan, line: nil)
        XCTAssertEqual(unknown.lineCode, "GO")
        XCTAssertNil(unknown.lineColorHex, "No line: a grey tile")
    }

    func testRidingSaysTheRideScreensLineAndCountsDownToYourStop() async throws {
        let rig = await DemoRideRig.started()
        let content = try content(rig)
        XCTAssertEqual(content.phase, .riding)
        XCTAssertEqual(content.title, "Clarkson in")
        XCTAssertEqual(try secondsLeft(content), 11 * 60, accuracy: 5, "On the device clock, to 5:43 on the engine's: your stop")
        XCTAssertEqual(content.minutes, "11 min", "Whole minutes, the ride screen's words (TT-219)")
        XCTAssertEqual(content.label, "Arrives")
        XCTAssertEqual(content.value, "5:43 PM")
        XCTAssertNil(content.delay)
        XCTAssertFalse(content.late)
        XCTAssertEqual(content.position, 3.25, accuracy: 0.01)
        XCTAssertFalse(content.isClose)
        XCTAssertFalse(content.isAlert)
        XCTAssertFalse(content.isGreen)
        XCTAssertEqual(content.now, "Now")
        XCTAssertEqual(content.updated, "Updated 5:32 PM")
    }

    func testAtTheStopBeforeYoursYourStopIsNext() async throws {
        let rig = await DemoRideRig.started(at: t(17, 36, 20))
        let content = try content(rig)
        XCTAssertEqual(content.phase, .atStation)
        XCTAssertEqual(content.title, "Clarkson is next")
        XCTAssertTrue(content.isClose)
        XCTAssertEqual(try secondsLeft(content), 400, accuracy: 5, "Still counting to your stop")
        XCTAssertEqual(content.value, "5:43 PM")
        XCTAssertEqual(content.position, 4)
    }

    func testYourStopNextCountsDownToYourStop() async throws {
        let rig = await DemoRideRig.started(at: t(17, 38))
        let content = try content(rig)
        XCTAssertEqual(content.phase, .yourStopNext)
        XCTAssertEqual(content.title, "Clarkson is next")
        XCTAssertEqual(try secondsLeft(content), 5 * 60, accuracy: 5)
        XCTAssertEqual(content.label, "Arrives")
        XCTAssertTrue(content.isClose)
        XCTAssertFalse(content.isAlert)
    }

    func testArrivingTurnsGreenWithNothingAtTheRight() async throws {
        let rig = await DemoRideRig.started(at: t(17, 42, 20))
        let content = try content(rig)
        XCTAssertEqual(content.phase, .arriving)
        XCTAssertTrue(content.isAlert)
        XCTAssertTrue(content.isGreen)
        XCTAssertEqual(content.title, "Arriving at Clarkson")
        XCTAssertEqual(content.label, "")
        XCTAssertNil(content.value)
        XCTAssertEqual(try secondsLeft(content), 40, accuracy: 5)
        XCTAssertEqual(content.minutes, "1 min", "Never under a minute")
        XCTAssertGreaterThan(content.position, 4)
        XCTAssertLessThan(content.position, 5)
    }

    func testAtYourStopItSaysNow() async throws {
        let rig = await DemoRideRig.started(at: t(17, 43, 5))
        let content = try content(rig)
        XCTAssertEqual(content.phase, .atYourStop)
        XCTAssertEqual(content.title, "This is Clarkson")
        XCTAssertNil(content.countdownEnd)
        XCTAssertNil(content.minutes)
        XCTAssertEqual(content.now, "Now")
        XCTAssertEqual(content.position, 5, "The train on the pin")
        XCTAssertTrue(content.isGreen)
        XCTAssertFalse(content.isAlert)

        // The ride ends 2 min later (D100) and its activity ends with the last card.
        rig.drive(to: t(17, 45, 10))
        XCTAssertEqual(rig.engine?.state?.phase, .ended)
        let ended = try self.content(rig)
        XCTAssertEqual(ended.phase, .atYourStop)
        XCTAssertEqual(ended.title, "This is Clarkson")
    }

    func testTheTwentyFourHourClockFormatsEveryTime() async throws {
        let rig = await DemoRideRig.started()
        let engine = try XCTUnwrap(rig.engine)
        let content = try XCTUnwrap(RideActivityAttributes.ContentState(
            plan: rig.plan, state: try XCTUnwrap(engine.state), now: engine.now, deviceNow: deviceNow,
            formatter: TimeFormatter(format: .twentyFourHour)
        ))
        XCTAssertEqual(content.value, "17:43")
        XCTAssertEqual(content.updated, "Updated 17:32")
    }

    func testAPushFromAnOlderServerStillDecodes() throws {
        // The alert server before TT-205 wrote these keys (TT-178); the card reads its title, countdown and label.
        let json = """
        {"phase":"countingDown","title":"5:13 PM to Clarkson","detail":"Check the board · On time","countdownEnd":1800000000,
        "now":"","time":"departs","departure":"Union 5:13 PM","arrival":"Clarkson 5:43 PM","arrives":"Arrives Clarkson 5:43 PM",
        "position":0,"button":"I’m on board","updated":"Updated 4:43 PM","platform":"Check the board","pill":false,"late":false}
        """
        let state = try JSONDecoder().decode(RideActivityAttributes.ContentState.self, from: Data(json.utf8))
        XCTAssertEqual(state.phase, .countingDown)
        XCTAssertEqual(state.title, "5:13 PM to Clarkson")
        XCTAssertEqual(state.countdownEnd, Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertNil(state.minutes, "No minutes: the card falls back to timer text")
        XCTAssertEqual(state.label, "Check the board")
        XCTAssertNil(state.platformNumber)

        // And what this app writes reads back the same.
        let again = try JSONDecoder().decode(RideActivityAttributes.ContentState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(again, state)
    }

    // MARK: Size

    func testTheActivityStaysWellUnderFourKilobytes() async throws {
        let rig = await DemoRideRig.started(at: t(17, 42, 20))
        let attributes = RideActivityAttributes(ride: DemoRide.ride(on: DemoRideRig.day), plan: rig.plan, line: DemoRide.line)
        var content = try content(rig)
        // The longest words GO's names give, to be sure.
        content.title = "Arriving at Bloomington"
        content.value = "12:59 PM"
        let size = try JSONEncoder().encode(attributes).count + JSONEncoder().encode(content).count
        XCTAssertLessThan(size, 1024, "Apple's limit is 4 KB for the attributes and the state together")
    }

    // MARK: Updates, the alert, the end

    func testAnUpdateGoesOutWhenSomethingVisibleChangesOrOnceAMinute() async throws {
        let rig = await DemoRideRig.started()
        let shown = try content(rig)
        var same = shown
        same.updated = "Updated 5:33 PM"
        same.position += 0.01
        same.countdownEnd = shown.countdownEnd?.addingTimeInterval(5)
        XCTAssertTrue(shown.looksLike(same))
        XCTAssertFalse(RideLiveActivity.needsUpdate(from: shown, to: same, sentAt: deviceNow, now: deviceNow.addingTimeInterval(20)))
        XCTAssertTrue(
            RideLiveActivity.needsUpdate(from: shown, to: same, sentAt: deviceNow, now: deviceNow.addingTimeInterval(60)),
            "Once a minute, to keep it from going stale"
        )
        XCTAssertTrue(RideLiveActivity.needsUpdate(from: shown, to: same, sentAt: nil, now: deviceNow))

        var moved = shown
        moved.position += 0.05
        XCTAssertFalse(shown.looksLike(moved))
        XCTAssertTrue(RideLiveActivity.needsUpdate(from: shown, to: moved, sentAt: deviceNow, now: deviceNow))

        var later = shown
        later.countdownEnd = shown.countdownEnd?.addingTimeInterval(60)
        XCTAssertFalse(shown.looksLike(later), "A train a minute late moves the countdown")

        var nextMinute = shown
        nextMinute.minutes = "10 min"
        XCTAssertFalse(shown.looksLike(nextMinute), "A new minute is sent (TT-219)")

        var renamed = shown
        renamed.title = "Clarkson is next"
        XCTAssertFalse(shown.looksLike(renamed))
    }

    func testArrivingAlertsOnce() async throws {
        let rig = await DemoRideRig.started(at: t(17, 38))
        let before = try content(rig)
        rig.drive(to: t(17, 42, 20))
        let arriving = try content(rig)
        rig.drive(to: t(17, 42, 40))
        let still = try content(rig)
        XCTAssertTrue(RideLiveActivity.alerts(from: before, to: arriving))
        XCTAssertFalse(RideLiveActivity.alerts(from: arriving, to: still))
        XCTAssertFalse(RideLiveActivity.alerts(from: before, to: before))
    }

    // MARK: Links

    func testTheLinksOpenTheRideAndEndIt() throws {
        XCTAssertEqual(RideActivityLink.open.url.absoluteString, "traintimes://ride")
        XCTAssertEqual(RideActivityLink.end.url.absoluteString, "traintimes://ride/end")
        XCTAssertEqual(RideActivityLink(RideActivityLink.open.url), .open)
        XCTAssertEqual(RideActivityLink(RideActivityLink.end.url), .end)
        XCTAssertNil(RideActivityLink(try XCTUnwrap(URL(string: "traintimes://ride/other"))))
        XCTAssertNil(RideActivityLink(try XCTUnwrap(URL(string: "traintimes://alerts"))))
        XCTAssertNil(RideActivityLink(try XCTUnwrap(URL(string: "https://traintimes.ca/ride"))))
    }
}
