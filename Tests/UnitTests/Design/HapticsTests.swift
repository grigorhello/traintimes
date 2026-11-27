import XCTest
@testable import TrainTimes

/// The feel kit (TT-214, D95): the bell's feels on each path, one per gesture, timed from the tap, and the switch's Click.
@MainActor
final class HapticsTests: XCTestCase {
    private let route = AlertFixtures.route
    private let trip = AlertFixtures.trip()

    // MARK: The bell

    /// A save back at once: Rail joint, once, and the wait tap never plays.
    func testFastSavePlaysRailJointOnly() async throws {
        let haptics = FakeHaptics()
        let bells = AlertBellModel(
            rules: AlertFixtures.rules(FakeAlertServer()), refusalDelay: .zero, afterPrompt: {}, haptics: haptics,
            slowSaveAfter: .milliseconds(40)
        )
        await bells.tap(trip, on: route)
        XCTAssertEqual(haptics.played, [.railJoint])
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(haptics.played, [.railJoint], "the wait tap was called off")
    }

    /// A save not back after the delay: the soft wait tap at once, then Rail joint when On lands.
    func testSlowSavePlaysTheWaitTapThenRailJoint() async {
        let haptics = FakeHaptics()
        let server = FakeAlertServer()
        await server.holdSaves()
        let bells = AlertBellModel(
            rules: AlertFixtures.rules(server), refusalDelay: .zero, afterPrompt: {}, haptics: haptics,
            slowSaveAfter: .milliseconds(20)
        )
        let start = ContinuousClock.now
        let tap = Task { await bells.tap(trip, on: route) }
        await server.waitUntilHolding()
        await eventually { haptics.played == [.wait] }
        XCTAssertGreaterThanOrEqual(haptics.times[0] - start, .milliseconds(20), "timed from the tap")
        XCTAssertEqual(bells.bell(for: trip, on: route), .waiting)
        await server.release()
        await tap.value
        XCTAssertEqual(haptics.played, [.wait, .railJoint])
        XCTAssertEqual(bells.bell(for: trip, on: route), .on)
    }

    /// Off is Tap.
    func testTurningOffPlaysTap() async {
        let haptics = FakeHaptics()
        let bells = AlertBellModel(
            rules: AlertFixtures.rules(FakeAlertServer()), refusalDelay: .zero, afterPrompt: {}, haptics: haptics,
            slowSaveAfter: .seconds(5)
        )
        await bells.tap(trip, on: route)
        await bells.tap(trip, on: route)
        XCTAssertEqual(haptics.played, [.railJoint, .tap])
    }

    /// Notifications off: Warning with the shake, and no Rail joint.
    func testARefusalPlaysWarning() async {
        let haptics = FakeHaptics()
        let rules = AlertRules(
            server: FakeAlertServer(), push: FixturePushRegistration(), permissions: SettableNotificationPermission(.off),
            defaults: nil
        )
        let bells = AlertBellModel(rules: rules, refusalDelay: .zero, afterPrompt: {}, haptics: haptics, slowSaveAfter: .seconds(5))
        await bells.tap(trip, on: route)
        XCTAssertEqual(haptics.played, [.warning])
        XCTAssertEqual(bells.shakes(for: trip), 1)
    }

    /// A save the server cannot take: Fail, and no Rail joint.
    func testAFailedSavePlaysFail() async {
        let haptics = FakeHaptics()
        let server = FakeAlertServer()
        await server.setFailing(true)
        let bells = AlertBellModel(
            rules: AlertFixtures.rules(server), refusalDelay: .zero, afterPrompt: {}, haptics: haptics, slowSaveAfter: .seconds(5)
        )
        await bells.tap(trip, on: route)
        XCTAssertEqual(haptics.played, [.fail])
        XCTAssertEqual(bells.capsule?.kind, .failed(.turnOn))
    }

    /// Trip details' bell model (`sibling()`) plays the same feels.
    func testTheSiblingKeepsThePlayer() async {
        let haptics = FakeHaptics()
        let bells = AlertBellModel(
            rules: AlertFixtures.rules(FakeAlertServer()), refusalDelay: .zero, afterPrompt: {}, haptics: haptics,
            slowSaveAfter: .seconds(5)
        )
        await bells.sibling().tap(trip, on: route)
        XCTAssertEqual(haptics.played, [.railJoint])
    }

    // MARK: The switch

    /// One Click as the thumb arrives, 140 ms after the tap, the same both ways; none for the option already chosen.
    func testTheSwitchClicksOnceAsTheThumbArrives() async {
        let haptics = FakeHaptics()
        let start = ContinuousClock.now
        await SwitchClick.tapped(from: TimeFormat.device, to: .twelveHour, haptics: haptics)?.value
        XCTAssertEqual(haptics.played, [.click])
        XCTAssertGreaterThanOrEqual(haptics.times[0] - start, SwitchClick.delay)

        await SwitchClick.tapped(from: TimeFormat.twelveHour, to: .device, haptics: haptics)?.value
        XCTAssertEqual(haptics.played, [.click, .click], "the same back")

        XCTAssertNil(SwitchClick.tapped(from: TimeFormat.device, to: .device, haptics: haptics))
        XCTAssertEqual(haptics.played, [.click, .click])
    }

    // MARK: Rail joint

    /// Two beats 100 ms apart, light then heavy and dull, with a short ring fading under the second.
    func testRailJointIsTwoBeatsLightThenHeavy() throws {
        let pattern = HapticFeel.railJointPattern
        let beats = pattern.events.filter { $0.kind == .transient }
        XCTAssertEqual(beats.map(\.time), [0, 0.1])
        XCTAssertEqual(beats.map(\.intensity), [0.55, 1])
        XCTAssertEqual(beats.map(\.sharpness), [0.30, 0.20])
        let ring = try XCTUnwrap(pattern.events.first { $0.kind == .continuous })
        XCTAssertEqual(ring.duration, 0.06)
        XCTAssertEqual(pattern.fade?.points.last?.value, 0)
        XCTAssertNoThrow(try ArrivingHaptics.pattern(pattern))
        XCTAssertEqual(HapticFeel.listed.count, 10)
    }

    // MARK: Alarm (TT-250, D127)

    /// Five strong, crisp transients 0.18 s apart: the wrong train warning, in the app once and on the card five times.
    func testAlarmIsFiveStrongBeats() throws {
        let pattern = HapticFeel.alarmPattern
        XCTAssertEqual(pattern.events.map(\.kind), Array(repeating: .transient, count: 5))
        let times = pattern.events.map(\.time)
        for (time, expected) in zip(times, [0, 0.18, 0.36, 0.54, 0.72]) {
            XCTAssertEqual(time, expected, accuracy: 0.0001)
        }
        XCTAssertEqual(pattern.events.map(\.intensity), Array(repeating: 1, count: 5))
        XCTAssertEqual(pattern.events.map(\.sharpness), Array(repeating: 0.6, count: 5))
        XCTAssertNoThrow(try ArrivingHaptics.pattern(pattern))
        XCTAssertTrue(HapticFeel.listed.contains(.alarm))
        XCTAssertEqual(HapticMoment.wrongTrain.feel, .alarm)
        XCTAssertEqual(HapticMoment.wrongTrain.delay, .zero)
    }

    private func eventually(
        _ condition: () async -> Bool, file: StaticString = #filePath, line: UInt = #line
    ) async {
        for _ in 0..<300 {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out", file: file, line: line)
    }
}
