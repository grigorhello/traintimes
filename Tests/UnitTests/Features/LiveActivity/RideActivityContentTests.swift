import XCTest
@testable import TrainTimes

/// TT-174: the ride as its Live Activity shows it, through the demo ride's moments (Live-Lock, Live-Island), its size,
/// and the rules that update, alert and end it.
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

    func testRidingShowsTheNextStopAndCountsDownToIt() async throws {
        let rig = await DemoRideRig.started()
        let content = try content(rig)
        XCTAssertEqual(content.phase, .riding)
        XCTAssertEqual(content.title, "Next stop · Port Credit")
        XCTAssertEqual(content.detail, "Clarkson 5:43 PM · 2 stops")
        XCTAssertEqual(try secondsLeft(content), 4 * 60, accuracy: 5, "On the device clock, to 5:36 on the engine's")
        XCTAssertEqual(content.time, "5:36 PM")
        XCTAssertEqual(content.departure, "Union Station 5:13 PM")
        XCTAssertEqual(content.arrival, "Clarkson 5:43 PM")
        XCTAssertEqual(content.position, 3.25, accuracy: 0.01)
        XCTAssertFalse(content.isAlert)
        XCTAssertEqual(content.button, "End ride")
        XCTAssertEqual(content.now, "Now")
        XCTAssertEqual(content.updated, "Updated 5:32 PM")
    }

    func testAtAStationTheTrainSitsOnItsDotAndSaysNow() async throws {
        let rig = await DemoRideRig.started(at: t(17, 36, 20))
        let content = try content(rig)
        XCTAssertEqual(content.phase, .atStation)
        XCTAssertEqual(content.title, "Now at · Port Credit")
        XCTAssertEqual(content.detail, "Your stop is next")
        XCTAssertNil(content.countdownEnd, "Now in place of the countdown")
        XCTAssertEqual(content.time, "5:36 PM")
        XCTAssertEqual(content.position, 4)
    }

    func testYourStopNextCountsDownToYourStop() async throws {
        let rig = await DemoRideRig.started(at: t(17, 38))
        let content = try content(rig)
        XCTAssertEqual(content.phase, .yourStopNext)
        XCTAssertEqual(content.title, "Next stop · Clarkson")
        XCTAssertEqual(content.detail, "Your stop is next")
        XCTAssertEqual(try secondsLeft(content), 5 * 60, accuracy: 5)
        XCTAssertEqual(content.time, "5:43 PM")
        XCTAssertFalse(content.isAlert)
    }

    func testArrivingTurnsGreen() async throws {
        let rig = await DemoRideRig.started(at: t(17, 42, 20))
        let content = try content(rig)
        XCTAssertEqual(content.phase, .arriving)
        XCTAssertTrue(content.isAlert)
        XCTAssertEqual(content.title, "Arriving at Clarkson")
        XCTAssertEqual(content.detail, "Your stop · doors in a minute")
        XCTAssertEqual(try secondsLeft(content), 40, accuracy: 5)
        XCTAssertGreaterThan(content.position, 4)
        XCTAssertLessThan(content.position, 5)
    }

    func testAtYourStopTheRideIsComplete() async throws {
        let rig = await DemoRideRig.started(at: t(17, 43, 5))
        let content = try content(rig)
        XCTAssertEqual(content.phase, .atYourStop)
        XCTAssertEqual(content.title, "This is your stop")
        XCTAssertEqual(content.detail, "Clarkson · Ride complete")
        XCTAssertNil(content.countdownEnd)
        XCTAssertEqual(content.position, 5, "The train on the pin")
        XCTAssertEqual(content.button, "Done")
        XCTAssertFalse(content.isAlert)

        // The ride ends 10 min later and its activity keeps the last card.
        rig.drive(to: t(17, 53, 10))
        XCTAssertEqual(rig.engine?.state?.phase, .ended)
        let ended = try self.content(rig)
        XCTAssertEqual(ended.phase, .atYourStop)
        XCTAssertEqual(ended.button, "Done")
    }

    func testTheTwentyFourHourClockFormatsEveryTime() async throws {
        let rig = await DemoRideRig.started()
        let engine = try XCTUnwrap(rig.engine)
        let content = try XCTUnwrap(RideActivityAttributes.ContentState(
            plan: rig.plan, state: try XCTUnwrap(engine.state), now: engine.now, deviceNow: deviceNow,
            formatter: TimeFormatter(format: .twentyFourHour)
        ))
        XCTAssertEqual(content.detail, "Clarkson 17:43 · 2 stops")
        XCTAssertEqual(content.time, "17:36")
        XCTAssertEqual(content.departure, "Union Station 17:13")
        XCTAssertEqual(content.updated, "Updated 17:32")
    }

    // MARK: Size

    func testTheActivityStaysWellUnderFourKilobytes() async throws {
        let rig = await DemoRideRig.started(at: t(17, 42, 20))
        let attributes = RideActivityAttributes(ride: DemoRide.ride(on: DemoRideRig.day), plan: rig.plan, line: DemoRide.line)
        var content = try content(rig)
        // The longest words GO's names give, to be sure.
        content.title = "Arriving at Bloomington"
        content.detail = String(repeating: "Exhibition 12:59 PM · 12 stops ", count: 2)
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

        var renamed = shown
        renamed.title = "Now at · Long Branch"
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

    func testTheActivityLeavesFifteenMinutesAfterYourStopOrAtOnceOnEndRide() {
        var state = RideState(
            phase: .ended, currentStop: nil, nextStop: nil, stopsLeft: 0, minutesToYourStop: 0,
            expectedArrival: t(17, 43), source: .phone, lastUpdate: t(17, 53), endReason: .arrived
        )
        // The engine ends the ride at 5:53:10; the activity stays until 5:58, 290 s on the device clock.
        let leaves = RideLiveActivity.dismissal(for: state, engineNow: t(17, 53, 10), deviceNow: deviceNow)
        XCTAssertEqual(leaves, deviceNow.addingTimeInterval(290))
        XCTAssertNil(RideLiveActivity.dismissal(for: state, engineNow: t(17, 59), deviceNow: deviceNow), "Already past: at once")

        for reason in [RideEndReason.byRider, .cancelled, .leftTheLine] {
            state.endReason = reason
            XCTAssertNil(RideLiveActivity.dismissal(for: state, engineNow: t(17, 40), deviceNow: deviceNow), "\(reason)")
        }
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
