import XCTest
@testable import TrainTimes

/// TT-251 (D127): the wrong train rule on `WrongWorld`'s straight tracks, with a clock in seconds after L (5:30 PM).
final class WrongTrainRuleTests: XCTestCase {
    private typealias World = WrongWorld

    private func finding(_ result: (verdict: WrongTrainRule.Verdict, second: Int)?, file: StaticString = #filePath, line: UInt = #line)
        -> (WrongTrainRule.Finding, Int)? {
        guard let result, case .wrong(let finding) = result.verdict else {
            XCTFail("no warning", file: file, line: line)
            return nil
        }
        return (finding, result.second)
    }

    /// T comes 6 km late from the west, at 25 m/s.
    private func lateT(_ rig: WrongRig) -> (Double) -> GeoPoint? {
        { rig.point("T", -6_000 - 25 * max(0, -$0)) }
    }

    /// The phone at O until `start`, then on trip `id`, and that train's positions with it.
    private func leaving(_ rig: WrongRig, _ id: String, at start: Double) -> (Double) -> GeoPoint {
        { rig.point(id, World.moving($0, from: start)) }
    }

    // MARK: Warns

    func testTheWrongWayFromAnOpenAirStation() throws {
        // An alert on the eastbound T; the phone leaves with the westbound before T comes.
        var rig = try WrongRig(candidates: [World.westbound(after: -300), World.express(after: 900)])
        rig.stops("WEST", ["W1", "W2"])
        let phone = leaving(rig, "WEST", at: -300)
        let result = finding(rig.run(from: -600, to: 0, phone: phone, trains: ["WEST": phone, "T": lateT(rig)]))
        let (found, second) = try XCTUnwrap(result)
        XCTAssertEqual(found.trip?.tripId, "WEST")
        XCTAssertEqual(found.reason, .wrongWay)
        XCTAssertEqual(found.evidence, .feed)
        XCTAssertEqual(found.nextStopId, "W1")
        XCTAssertEqual(found.nextStopTime, World.departure.addingTimeInterval(300))
        XCTAssertLessThanOrEqual(second, -120, "within about 3 min of leaving")
        XCTAssertGreaterThan(found.seconds, 60)
    }

    func testAnExpressThatSkipsTheStopFromUnionOnARide() throws {
        // Under Union's roof until the train is 300 m out; T stands at its platform.
        var rig = try WrongRig(origin: "UN", tie: .rideAtOrigin, candidates: [World.express(after: -120)])
        let geo = rig
        rig.stops("EXPRESS", ["E3"])
        rig.stops("T", ["UN", "E1", "D"])
        let phone = leaving(rig, "EXPRESS", at: -120)
        let result = finding(rig.run(
            from: -600, to: 180, phone: phone, trains: ["EXPRESS": phone, "T": { _ in geo.point("T", 0) }],
            accuracy: { World.moving($0, from: -120) < 300 ? 200 : 8 }
        ))
        let (found, _) = try XCTUnwrap(result)
        XCTAssertEqual(found.reason, .skipsStop)
        XCTAssertEqual(found.nextStopId, "E3")
    }

    func testAnotherLineFromUnionOnceTheTracksPart() throws {
        // T and the other line leave Union 30 s apart on the same track, which parts 800 m out.
        var rig = try WrongRig(origin: "UN", tie: .rideAtOrigin, candidates: [World.otherLine(after: 30)])
        let geo = rig
        rig.stops("OTHER", ["N1"])
        let phone = leaving(rig, "OTHER", at: 30)
        let result = finding(rig.run(
            from: -300, to: 420, phone: phone, trains: ["OTHER": phone, "T": { geo.point("T", World.moving($0, from: 0)) }],
            accuracy: { World.moving($0, from: 30) < 300 ? 200 : 8 }
        ))
        let (found, second) = try XCTUnwrap(result)
        XCTAssertEqual(found.reason, .otherLine)
        XCTAssertEqual(found.nextStopId, "N1")
        XCTAssertGreaterThan(World.moving(Double(second), from: 30), 800 + 250, "not before the tracks part")
    }

    func testTheMissedTrain() throws {
        // T leaves at L; the phone stays on the platform and leaves 10 min later on the westbound.
        var rig = try WrongRig(candidates: [World.westbound(after: 600)])
        let geo = rig
        rig.stops("WEST", ["W1", "W2"])
        let phone = leaving(rig, "WEST", at: 600)
        let result = finding(rig.run(
            from: -120, to: 900, phone: phone, trains: ["WEST": phone, "T": { geo.point("T", World.moving($0, from: 0)) }]
        ))
        let (found, second) = try XCTUnwrap(result)
        XCTAssertEqual(found.reason, .wrongWay)
        XCTAssertGreaterThan(second, 600)
    }

    func testARideStartedAfterTLeftWithNoFixAtTheStation() throws {
        var rig = try WrongRig(tie: .rideAfterLeft, candidates: [World.westbound(after: 600)])
        let geo = rig
        rig.stops("WEST", ["W1", "W2"])
        let train = leaving(rig, "WEST", at: 600)
        let result = finding(rig.run(
            from: 600, to: 900, phone: { $0 >= 660 ? train($0) : nil },
            trains: ["WEST": train, "T": { geo.point("T", World.moving($0, from: 0)) }]
        ))
        XCTAssertEqual(try XCTUnwrap(result).0.reason, .wrongWay)
    }

    func testTheWrongWayByTheTrackWithNoFeed() throws {
        var rig = try WrongRig(tie: .rideAtOrigin, candidates: [])
        let geo = rig
        let result = finding(rig.run(from: -300, to: 200, phone: { geo.point("T", -World.moving($0, from: 0)) }))
        let (found, _) = try XCTUnwrap(result)
        XCTAssertEqual(found.evidence, .track)
        XCTAssertEqual(found.reason, .wrongWay)
        XCTAssertNil(found.trip)
        XCTAssertEqual(found.nextStopId, "W1", "the nearest station of T's line behind O")
        XCTAssertNil(found.nextStopTime)
    }

    // MARK: Never warns

    private func neverWarns(
        _ rig: inout WrongRig, from: Int, to: Int, phone: (Double) -> GeoPoint?, trains: [String: (Double) -> GeoPoint?] = [:],
        timed: Bool = true, accuracy: (Double) -> Double = { _ in 8 }, stationary: (Double) -> Bool = { _ in false },
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let result = rig.run(from: from, to: to, phone: phone, trains: trains, timed: timed, accuracy: accuracy, stationary: stationary)
        XCTAssertNil(result, "warned at \(result?.second ?? 0) s", file: file, line: line)
    }

    func testATrainRunningIntoTheStation() throws {
        var rig = try WrongRig(candidates: [World.westbound(after: 0)])
        let geo = rig
        rig.stops("WEST", ["W1", "W2"])
        // The phone comes in on the westbound from 2 km east and stays at O; the train goes on.
        let phone: (Double) -> GeoPoint = { geo.point("WEST", min(0, -2_000 + 25 * ($0 + 80))) }
        neverWarns(&rig, from: -120, to: 400, phone: phone, trains: [
            "WEST": { $0 < 0 ? phone($0) : geo.point("WEST", World.moving($0, from: 0)) }, "T": lateT(rig),
        ])
    }

    func testACarBesideTheLine() throws {
        var rig = try WrongRig(candidates: [World.westbound(after: -300)])
        let geo = rig
        rig.stops("WEST", ["W1", "W2"])
        let train = leaving(rig, "WEST", at: -300)
        neverWarns(&rig, from: -600, to: 0, phone: { geo.point("WEST", World.moving($0, from: -300), north: 250) }, trains: [
            "WEST": train, "T": lateT(rig),
        ])
    }

    func testTwoTrainsLeavingTogetherOnTheSameTrackWhileTIsQuiet() throws {
        var rig = try WrongRig(candidates: [World.express(after: -90)])
        rig.stops("EXPRESS", ["E3"])
        let phone = leaving(rig, "EXPRESS", at: -90)
        neverWarns(&rig, from: -400, to: 400, phone: phone, trains: ["EXPRESS": phone])
    }

    func testTCancelledOrSkippingTheStopIsQuiet() throws {
        for (cancelled, skipped) in [(true, Set<String>()), (false, ["D"]), (false, ["O"])] {
            var rig = try WrongRig(candidates: [World.westbound(after: -300)])
            rig.stops("WEST", ["W1", "W2"])
            rig.stops("T", ["O", "E1", "D"], cancelled: cancelled, skipped: skipped)
            let phone = leaving(rig, "WEST", at: -300)
            neverWarns(&rig, from: -600, to: 0, phone: phone, trains: ["WEST": phone, "T": lateT(rig)])
            XCTAssertEqual(rig.verdict(0), .quiet)
        }
    }

    func testAJumpyFixUnderUnionsRoof() throws {
        var rig = try WrongRig(origin: "UN", tie: .rideAtOrigin, candidates: [World.express(after: -120)])
        let geo = rig
        rig.stops("EXPRESS", ["E3"])
        rig.stops("T", ["UN", "E1", "D"])
        let jumps: [Double: Double] = [-100: 500, -99: 520]
        neverWarns(
            &rig, from: -600, to: 300, phone: { geo.point("EXPRESS", jumps[$0] ?? 0) },
            trains: ["EXPRESS": { geo.point("EXPRESS", World.moving($0, from: -120)) }, "T": { _ in geo.point("T", 0) }],
            accuracy: { jumps[$0] == nil ? 200 : 8 }
        )
    }

    func testAnEarlierTrainThatAlsoStopsAtTheStop() throws {
        var rig = try WrongRig(candidates: [World.candidate("LOCAL", after: -600, shape: World.east, stops: ["E1", "D", "E3"])])
        rig.stops("LOCAL", ["E1", "D", "E3"])
        let phone = leaving(rig, "LOCAL", at: -600)
        neverWarns(&rig, from: -900, to: -200, phone: phone, trains: ["LOCAL": phone, "T": lateT(rig)])
        XCTAssertEqual(rig.verdict(-200), .quiet)
    }

    func testOnBoardTappedAwayFromTheStationThenMovingAlongTheLine() throws {
        var rig = try WrongRig(tie: .rideAtOrigin, candidates: [World.express(after: -300)])
        let geo = rig
        rig.stops("EXPRESS", ["E3"])
        rig.stops("T", ["O", "E1", "D"])
        // The phone is never at O: its first fix is 2 km out, on the train.
        let train: (Double) -> GeoPoint = { geo.point("EXPRESS", 2_000 + World.moving($0, from: -300)) }
        neverWarns(&rig, from: -200, to: 100, phone: train, trains: ["EXPRESS": train, "T": { _ in geo.point("T", 0) }])
    }

    func testTwoCandidatesMatchingWait() throws {
        var rig = try WrongRig(candidates: [World.westbound("WEST", after: -300), World.westbound("WEST2", after: -280)])
        rig.stops("WEST", ["W1", "W2"])
        rig.stops("WEST2", ["W1", "W2"])
        let phone = leaving(rig, "WEST", at: -300)
        neverWarns(&rig, from: -600, to: 0, phone: phone, trains: ["WEST": phone, "WEST2": phone, "T": lateT(rig)])
        guard case .following = rig.verdict(0) else { return XCTFail("waits, following") }
    }

    func testNoFreshUpdateForTheTrainNeverWarns() throws {
        var rig = try WrongRig(candidates: [World.westbound(after: -300)])
        rig.stops("WEST", ["W1", "W2"], fresh: false)
        let phone = leaving(rig, "WEST", at: -300)
        neverWarns(&rig, from: -600, to: 0, phone: phone, trains: ["WEST": phone, "T": lateT(rig)])
        guard case .following = rig.verdict(0) else { return XCTFail("following") }
    }

    func testUntimedPositionsNeverMatch() throws {
        var rig = try WrongRig(candidates: [World.westbound(after: -300)])
        rig.stops("WEST", ["W1", "W2"])
        let phone = leaving(rig, "WEST", at: -300)
        neverWarns(&rig, from: -600, to: 0, phone: phone, trains: ["WEST": phone, "T": lateT(rig)], timed: false)
    }

    func testAPhoneStandingStill() throws {
        var rig = try WrongRig(candidates: [World.westbound(after: -300)])
        let geo = rig
        rig.stops("WEST", ["W1", "W2"])
        neverWarns(
            &rig, from: -600, to: 0, phone: { _ in geo.point("WEST", 0) },
            trains: ["WEST": leaving(rig, "WEST", at: -300), "T": lateT(rig)], stationary: { _ in true }
        )
        XCTAssertEqual(rig.verdict(0), .quiet)
    }

    func testTheTrackProofDoesNotApplyWhereTsTrackStartsAtTheStation() throws {
        var rig = try WrongRig(tie: .rideAtOrigin, shape: World.fromOrigin, candidates: [])
        neverWarns(&rig, from: -300, to: 300, phone: { World.at(-World.moving($0, from: 0)) })
    }

    func testTheTrackProofIsForRidesOnly() throws {
        var rig = try WrongRig(tie: .alert, candidates: [])
        let geo = rig
        neverWarns(&rig, from: -300, to: 300, phone: { geo.point("T", -World.moving($0, from: 0)) })
    }

    // MARK: With your train, following

    func testWithTheTrainWhenThePhoneMovesWithT() throws {
        var rig = try WrongRig(candidates: [World.westbound(after: -300), World.express(after: 900)])
        let geo = rig
        let phone: (Double) -> GeoPoint = { geo.point("T", World.moving($0, from: 0)) }
        let result = rig.run(from: -300, to: 300, phone: phone, trains: ["T": phone], stopAt: { $0 == .withTrain })
        XCTAssertNotNil(result)
    }

    func testATwinKeepsWithTheTrainBackUntilTheTracksPart() throws {
        // On T, with the other line leaving 30 s later on the same track: not with T until the phone left its track.
        var rig = try WrongRig(origin: "UN", tie: .rideAtOrigin, candidates: [World.otherLine(after: 30)])
        let geo = rig
        rig.stops("OTHER", ["N1"])
        let phone: (Double) -> GeoPoint = { geo.point("T", World.moving($0, from: 0)) }
        let result = rig.run(
            from: -300, to: 400, phone: phone,
            trains: ["T": phone, "OTHER": { geo.point("OTHER", World.moving($0, from: 30)) }],
            accuracy: { World.moving($0, from: 0) < 300 ? 200 : 8 },
            stopAt: { if case .wrong = $0 { true } else { $0 == .withTrain } }
        )
        XCTAssertEqual(result?.verdict, .withTrain)
        XCTAssertGreaterThan(World.moving(Double(result?.second ?? 0), from: 0), 800 + 250)
    }

    func testFollowingBeforeTheProofIsComplete() throws {
        var rig = try WrongRig(candidates: [World.westbound(after: -300)])
        rig.stops("WEST", ["W1", "W2"])
        let phone = leaving(rig, "WEST", at: -300)
        var copy = rig
        let following = rig.run(from: -600, to: 0, phone: phone, trains: ["WEST": phone, "T": lateT(rig)], stopAt: {
            if case .following = $0 { true } else { false }
        })
        let warned = copy.run(from: -600, to: 0, phone: phone, trains: ["WEST": phone, "T": lateT(copy)])
        let first = try XCTUnwrap(following)
        XCTAssertLessThan(first.second, try XCTUnwrap(warned).second)
        guard case .following(let since) = first.verdict else { return XCTFail() }
        XCTAssertGreaterThan(since, World.departure.addingTimeInterval(-300), "since the first moving fix")
    }
}
