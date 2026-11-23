import XCTest
@testable import TrainTimes

/// The automatic start rule (TT-242, D120) on the synthetic track, in seconds after L: the phone at the station from 5 min
/// before, leaving with the train at 10 s; GO's positions every 30 s, 40 s late; leftAt 60 s.
final class AutoRideRuleTests: XCTestCase {
    private let atStation: (Double) -> (along: Double, north: Double, stationary: Bool)? = { _ in (0, 0, false) }

    // MARK: The start

    func testStartsWhenThePhoneLeavesWithTheTrain() throws {
        var rig = try RuleRig()
        let result = rig.run(from: -300, to: 400)
        XCTAssertEqual(result?.verdict, .starts)
        // Tp at 45 s, Y2 by 90 s, the positions reported at 60 and 90 s read by 130 s.
        XCTAssertEqual(result?.second, 130)
    }

    func testNoVerdictWhileLeftAtIsUnknown() throws {
        var rig = try RuleRig()
        XCTAssertNil(rig.run(from: -300, to: 600, left: nil))
    }

    func testANoOrARideKeepsItWaiting() throws {
        var rig = try RuleRig()
        rig.answered = true
        XCTAssertNil(rig.run(from: -300, to: 600))
    }

    // MARK: Y1

    func testNeverAtTheStationIsUnsure() throws {
        var rig = try RuleRig()
        let result = rig.run(from: -300, to: 400, phone: { $0 >= 60 ? (AutoRideFixtures.boarding($0), 0, false) : nil })
        XCTAssertEqual(result?.verdict, .unsure(.noStation))
        XCTAssertEqual(result?.second, 240)
    }

    /// The phone's fixes once the train is 400 m out, with no fix near the station before them.
    private let outOnly: (Double) -> (along: Double, north: Double, stationary: Bool)? = { s in
        let along = AutoRideFixtures.boarding(s)
        return along >= 400 ? (along, 0, false) : nil
    }

    func testAStationFixMoreThan15MinutesBeforeDoesNotCount() throws {
        var rig = try RuleRig()
        rig.phone(-20 * 60, along: 0)
        let result = rig.run(from: -300, to: 400, phone: outOnly)
        XCTAssertEqual(result?.verdict, .unsure(.noStation))
    }

    func testAStationaryFixHoldsWhileItIsTheLatest() throws {
        var rig = try RuleRig()
        // Still on the platform from 20 min before: held until 10 min before, inside the 15 min.
        rig.phone(-20 * 60, along: 0, stationary: true)
        let result = rig.run(from: -300, to: 400, phone: outOnly)
        XCTAssertEqual(result?.verdict, .starts)
    }

    func testAStationaryFixHeldTooLongDoesNotCount() throws {
        var rig = try RuleRig()
        rig.phone(-30 * 60, along: 0, stationary: true)
        let result = rig.run(from: -300, to: 400, phone: outOnly)
        XCTAssertEqual(result?.verdict, .unsure(.noStation))
    }

    func testUnionTakesTheCoveredForm() throws {
        var rig = try RuleRig(origin: "UN")
        // No good fix under the shed; the first after L − 60 s is 300 m out and the next farther on.
        let result = rig.run(from: -300, to: 400, phone: { s in
            let along = AutoRideFixtures.boarding(s)
            return along >= 300 ? (along, 0, false) : nil
        })
        XCTAssertEqual(result?.verdict, .starts)
    }

    func testUnionDoesNotTakeAPlatformFix() throws {
        var rig = try RuleRig(origin: "UN")
        let result = rig.run(from: -300, to: 400)
        XCTAssertEqual(result?.verdict, .unsure(.noStation))
    }

    func testTheCoveredFormNeedsTheNextFixFartherOn() throws {
        var rig = try RuleRig(origin: "UN")
        rig.phone(50, along: 400)
        rig.phone(51, along: 380)
        let result = rig.run(from: 52, to: 400, phone: { s in s >= 60 ? (AutoRideFixtures.boarding(s), 0, false) : nil })
        XCTAssertEqual(result?.verdict, .unsure(.noStation))
    }

    func testAWatchArmedAfterLTakesTheCoveredFormAnywhere() throws {
        var rig = try RuleRig(origin: "EX", armedLate: true)
        let result = rig.run(from: 0, to: 400, phone: { s in
            let along = AutoRideFixtures.boarding(s)
            return along >= 300 ? (along, 0, false) : nil
        })
        XCTAssertEqual(result?.verdict, .starts)
    }

    // MARK: Y2

    func testATenSecondGapOnIOS17StartsTheLeavingAgain() throws {
        var ios17 = try RuleRig(reportsStationary: false)
        var ios18 = try RuleRig(reportsStationary: true)
        // No fix from 60 to 72 s.
        let gap: (Double) -> (along: Double, north: Double, stationary: Bool)? = { s in
            (60..<72).contains(s) ? nil : (AutoRideFixtures.boarding(s), 0, false)
        }
        XCTAssertEqual(ios18.run(from: -300, to: 400, phone: gap)?.second, 130)
        let late = ios17.run(from: -300, to: 400, phone: gap)
        XCTAssertEqual(late?.verdict, .starts)
        // The 45 s from 72 s: 117 s, and the positions are already in.
        XCTAssertEqual(late?.second, 130)
        // At 116 s the iOS 17 leaving has not held for 45 s since the gap.
        var check = try RuleRig(reportsStationary: false)
        _ = check.run(from: -300, to: 116, phone: gap, stopAt: { _ in false })
        check.train(120, along: AutoRideFixtures.boarding(120), lag: -4)
        XCTAssertEqual(check.verdict(116), .waiting)
    }

    func testATwentySecondGapStartsTheLeavingAgainOnBoth() throws {
        var rig = try RuleRig(reportsStationary: true)
        let gap: (Double) -> (along: Double, north: Double, stationary: Bool)? = { s in
            (80..<101).contains(s) ? nil : (AutoRideFixtures.boarding(s), 0, false)
        }
        let result = rig.run(from: -300, to: 400, phone: gap)
        XCTAssertEqual(result?.verdict, .starts)
        // The 45 s again from 101 s; the position reported at 90 s falls in the gap, so the one at 120 s (read at 160 s)
        // makes the pair.
        XCTAssertEqual(result?.second, 160)
    }

    func testAStandstillStartsTheLeavingAgain() throws {
        var rig = try RuleRig()
        // The train stands 25 s at 380 m, then goes on: under 2 m/s over 8 s for more than 10 s.
        let stops: (Double) -> Double = { s in
            let reach = 49.0
            if s < reach { return AutoRideFixtures.boarding(s) }
            if s < reach + 25 { return AutoRideFixtures.boarding(reach) }
            return AutoRideFixtures.boarding(s - 25)
        }
        let result = rig.run(from: -300, to: 500, phone: { (stops($0), 0, false) }, train: { stops($0) })
        XCTAssertEqual(result?.verdict, .starts)
        // The 45 s again once it moves at 74 s.
        XCTAssertGreaterThanOrEqual(result?.second ?? 0, 119)
    }

    func testFixesOffTheTrackAreWeak() throws {
        var rig = try RuleRig()
        let result = rig.run(from: -300, to: 400, phone: { s in
            let along = AutoRideFixtures.boarding(s)
            return (along, along > 100 ? 200 : 0, false)
        })
        XCTAssertEqual(result?.verdict, .unsure(.weakFixes))
    }

    func testInaccurateFixesAreNotGood() throws {
        var rig = try RuleRig()
        for second in -300...400 {
            let s = Double(second)
            rig.phone(s, along: AutoRideFixtures.boarding(s), accuracy: s < 0 ? 8 : 150)
            if second % 30 == 0 { rig.train(s - 40, along: AutoRideFixtures.boarding(s - 40)) }
        }
        rig.leftAt = rig.time(60)
        XCTAssertEqual(rig.verdict(400), .unsure(.noFeed))
    }

    // MARK: Y3

    func testAPhoneAndATrainStandingAtThePlatformDoNotStart() throws {
        var rig = try RuleRig()
        // Both at the platform with positions; the phone leaves, the train's positions after Tp never come.
        let result = rig.run(from: -300, to: 400, train: { s in s < 45 ? 0 : nil })
        XCTAssertEqual(result?.verdict, .unsure(.noFeed))
    }

    func testPositionsWithoutTheVehiclesTimeDoNotCount() throws {
        var rig = try RuleRig()
        for second in stride(from: -300, through: 400, by: 1) {
            let s = Double(second)
            rig.leftAt = s >= 60 ? rig.time(60) : nil
            rig.phone(s, along: AutoRideFixtures.boarding(s))
            if second % 30 == 10 { rig.train(s - 40, along: AutoRideFixtures.boarding(s - 40), vehicleTime: false) }
        }
        XCTAssertEqual(rig.verdict(400), .unsure(.noFeed))
    }

    func testPositionsReadTooLateDoNotCount() throws {
        var rig = try RuleRig()
        _ = rig.run(from: -300, to: 400, train: nil, stopAt: { _ in false })
        rig.train(60, along: AutoRideFixtures.boarding(60), lag: 95)
        rig.train(90, along: AutoRideFixtures.boarding(90), lag: 95)
        XCTAssertEqual(rig.verdict(400), .unsure(.noFeed))
    }

    func testAGapThatChangesTooMuchDoesNotAgree() throws {
        var rig = try RuleRig()
        _ = rig.run(from: -300, to: 200, train: nil, stopAt: { _ in false })
        // 300 m behind, then 50 m ahead: both within 400 m, but the gap moved 350 m.
        rig.train(60, along: AutoRideFixtures.boarding(60) - 300, lag: 10)
        rig.train(90, along: AutoRideFixtures.boarding(90) + 50, lag: 10)
        XCTAssertEqual(rig.verdict(200), .waiting)
        XCTAssertEqual(rig.verdict(240), .unsure(.noFeed))
    }

    func testTwoPositionsLessThan20SecondsApartDoNotAgree() throws {
        var rig = try RuleRig()
        _ = rig.run(from: -300, to: 300, train: nil, stopAt: { _ in false })
        rig.train(60, along: AutoRideFixtures.boarding(60), lag: 10)
        rig.train(75, along: AutoRideFixtures.boarding(75), lag: 10)
        XCTAssertEqual(rig.verdict(300), .unsure(.noFeed))
    }

    // MARK: Y4

    func testARivalOnTheSameTrackBlocksTheStart() throws {
        var rig = try RuleRig()
        rig.rule.setRivals([AutoRideFixtures.rival(rig.plan)])
        XCTAssertEqual(rig.run(from: -300, to: 400)?.verdict, .unsure(.rival))
    }

    func testARivalWhoseTrackPartsIsLetGo() throws {
        var rig = try RuleRig()
        rig.rule.setRivals([AutoRideFixtures.rival(rig.plan, shape: AutoRideFixtures.parting(rig.plan, after: 700))])
        let result = rig.run(from: -300, to: 400)
        XCTAssertEqual(result?.verdict, .starts)
    }

    func testARivalOnAnotherTrackIsNoRival() throws {
        var rig = try RuleRig()
        rig.rule.setRivals([AutoRideFixtures.rival(rig.plan, shape: AutoRideFixtures.parting(rig.plan, after: 0))])
        XCTAssertEqual(rig.run(from: -300, to: 400)?.second, 130)
    }

    func testARivalLeavingLongAfterIsNoRival() throws {
        var rig = try RuleRig()
        rig.rule.setRivals([AutoRideFixtures.rival(rig.plan, after: 200)])
        XCTAssertEqual(rig.run(from: -300, to: 400)?.verdict, .starts)
    }

    func testARivalFarFromThePhoneIsLetGo() throws {
        var rig = try RuleRig()
        rig.rule.setRivals([AutoRideFixtures.rival(rig.plan)])
        _ = rig.run(from: -300, to: 125, stopAt: { _ in false })
        // Still at the platform when the phone is 1 km out.
        rig.rival("RIVAL", 90, along: 0, lag: 30)
        XCTAssertEqual(rig.run(from: 126, to: 400)?.verdict, .starts)
    }

    func testARivalFallingBehindIsLetGo() throws {
        var rig = try RuleRig()
        rig.rule.setRivals([AutoRideFixtures.rival(rig.plan)])
        _ = rig.run(from: -300, to: 125, stopAt: { _ in false })
        XCTAssertEqual(rig.verdict(125), .waiting)
        // 500 m behind at two positions 30 s apart: under 800 m away, more than 400 m along.
        rig.rival("RIVAL", 60, along: AutoRideFixtures.boarding(60) - 500, lag: 30)
        rig.rival("RIVAL", 90, along: AutoRideFixtures.boarding(90) - 500, lag: 30)
        XCTAssertEqual(rig.run(from: 126, to: 400)?.second, 130)
    }

    func testARivalWithNoFreshPositionStaysARival() throws {
        var rig = try RuleRig()
        rig.rule.setRivals([AutoRideFixtures.rival(rig.plan)])
        rig.rival("RIVAL", -400, along: 0, lag: 30)
        _ = rig.run(from: -300, to: 125, stopAt: { _ in false })
        // Far away, but read too late.
        rig.rival("RIVAL", 90, along: -2000, lag: 120)
        XCTAssertEqual(rig.run(from: 126, to: 400)?.verdict, .unsure(.rival))
    }

    // MARK: Y5

    func testLessThanFiveMinutesToTheStopIsShort() throws {
        var rig = try RuleRig()
        rig.arrival = rig.time(6 * 60)
        let result = rig.run(from: -300, to: 400)
        XCTAssertEqual(result?.verdict, .unsure(.short))
        XCTAssertEqual(result?.second, 240)
    }

    // MARK: Not on board

    func testAPhoneThatStayedIsNotOnBoard() throws {
        var rig = try RuleRig()
        let result = rig.run(from: -300, to: 400, phone: atStation)
        XCTAssertEqual(result?.verdict, .notOnBoard)
        // 60 s of fixes after leftAt, and the train placed 800 m along (reported at 90 s, read at 130 s).
        XCTAssertEqual(result?.second, 130)
    }

    func testAHeldStationaryFixThatStayedIsNotOnBoard() throws {
        var rig = try RuleRig()
        rig.phone(-120, along: 20, stationary: true)
        let result = rig.run(from: -100, to: 400, phone: { _ in nil })
        XCTAssertEqual(result?.verdict, .notOnBoard)
    }

    func testAPhoneThatStayedWithNoFeedIsNotDecided() throws {
        var rig = try RuleRig()
        let result = rig.run(from: -300, to: 400, phone: atStation, train: nil)
        XCTAssertEqual(result?.verdict, .unsure(.noFeed))
    }

    func testMissingFixesNeverSayStayed() throws {
        var rig = try RuleRig()
        let result = rig.run(from: -300, to: 400, phone: { s in s < 55 ? (0, 0, false) : nil })
        XCTAssertEqual(result?.verdict, .unsure(.noFeed))
    }

    func testAPhoneOffTheTrackFor60SecondsIsNotOnBoard() throws {
        var rig = try RuleRig()
        let result = rig.run(from: -300, to: 400, phone: { s in s < 70 ? (0, 0, false) : (0, 500, false) })
        XCTAssertEqual(result?.verdict, .notOnBoard)
        XCTAssertEqual(result?.second, 130)
    }

    func testAPhoneFarAwayAsTheTrainLeftIsNotOnBoard() throws {
        var rig = try RuleRig()
        let result = rig.run(from: 50, to: 400, phone: { _ in (3000, 600, false) })
        XCTAssertEqual(result?.verdict, .notOnBoard)
        XCTAssertEqual(result?.second, 60)
    }

    // MARK: Times

    func testTheDeadlineIsCappedAtLPlusSixMinutes() throws {
        var rig = try RuleRig()
        let result = rig.run(from: -300, to: 600, left: 300, phone: atStation, train: nil)
        XCTAssertEqual(result?.second, 360)
    }

    func testAStartIsStillAllowedAfterTheDeadline() throws {
        var rig = try RuleRig()
        _ = rig.run(from: -300, to: 289, train: nil, stopAt: { _ in false })
        XCTAssertEqual(rig.verdict(240), .unsure(.noFeed))
        rig.train(240, along: AutoRideFixtures.boarding(240), lag: 20)
        rig.train(270, along: AutoRideFixtures.boarding(270), lag: 20)
        XCTAssertEqual(rig.run(from: 290, to: 300, train: nil)?.verdict, .starts)
    }

    func testLeftAtIsTheLookThatSawItLeave() throws {
        let departure = Date(timeIntervalSince1970: 1_000_000)
        let look = departure.addingTimeInterval(50)
        XCTAssertEqual(
            AutoRideRule.leftAt(look: look, previous: look.addingTimeInterval(-15), departure: departure, sighted: true), look
        )
        // After a 2 min suspension: the look before, or L if that was earlier.
        XCTAssertEqual(
            AutoRideRule.leftAt(look: look, previous: look.addingTimeInterval(-120), departure: departure, sighted: true),
            departure
        )
        XCTAssertEqual(
            AutoRideRule.leftAt(
                look: look.addingTimeInterval(200), previous: look, departure: departure, sighted: true
            ),
            look
        )
        // With no fresh position: L.
        XCTAssertEqual(AutoRideRule.leftAt(look: look, previous: nil, departure: departure, sighted: false), departure)
    }

    func testAPlanWithNoTrackCannotBeChecked() throws {
        let plan = try OnBoardFixtures.plan()
        XCTAssertNil(AutoRideRule(
            plan: RidePlan(stops: plan.stops, track: nil), originId: "EX", armedLate: false, reportsStationary: true
        ))
    }
}
