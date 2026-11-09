import XCTest
@testable import TrainTimes

/// TT-158, D51: Settings › Testing › Mock time pretends it is another date and time, and keeps running from there.
final class MockTimeTests: XCTestCase {
    /// 11:58 PM in Toronto on Thu Nov 5 2026 (EST).
    private let lateEvening = Date(timeIntervalSince1970: 1_793_941_080)
    private let setAt = Date(timeIntervalSince1970: 1_000_000_000)

    func testTheMockedClockRunsOnFromTheChosenMoment() {
        let setting = MockTimeSetting(start: lateEvening, setAt: setAt)
        XCTAssertEqual(setting.now(real: setAt), lateEvening)
        XCTAssertEqual(setting.now(real: setAt.addingTimeInterval(150)), lateEvening.addingTimeInterval(150))
        XCTAssertEqual(setting.now(real: setAt.addingTimeInterval(-60)), lateEvening, "Never before the chosen moment")
    }

    func testClockIsTheBaseClockWithMockTimeOff() {
        let base = FixedClock(now: lateEvening)
        let real = setAt
        let clock = MockTimeClock(base: base, setting: { nil }, real: { real })
        XCTAssertEqual(clock.now, lateEvening)
    }

    func testClockReadsTheSettingOnEachCall() {
        // `@unchecked Sendable` is safe: the test reads and writes the box on its own thread only, one call at a time.
        final class Box: @unchecked Sendable {
            var setting: MockTimeSetting?
            var real = Date(timeIntervalSince1970: 1_000_000_000)
        }
        let box = Box()
        let base = FixedClock(now: Date(timeIntervalSince1970: 5))
        let clock = MockTimeClock(base: base, setting: { box.setting }, real: { box.real })
        XCTAssertEqual(clock.now, base.now)

        box.setting = MockTimeSetting(start: lateEvening, setAt: box.real)
        XCTAssertEqual(clock.now, lateEvening)
        box.real = box.real.addingTimeInterval(120)
        XCTAssertEqual(clock.now, lateEvening.addingTimeInterval(120), "Two minutes later it is 12:00 AM")

        box.setting = nil
        XCTAssertEqual(clock.now, base.now, "Use real time")
    }

    func testStoredOnDeviceAndRemovedWhenOff() {
        let defaults = UserDefaults.ephemeral()
        XCTAssertNil(MockTime.read(from: defaults))
        let setting = MockTimeSetting(start: lateEvening, setAt: setAt)
        MockTime.write(setting, to: defaults)
        XCTAssertEqual(MockTime.read(from: defaults), setting)
        MockTime.write(nil, to: defaults)
        XCTAssertNil(MockTime.read(from: defaults))
    }

    /// A UI test sets it with `-settings.mockTime <seconds>` alone: it runs from the start of the run.
    func testStartAloneRunsFromTheStartOfTheRun() {
        let defaults = UserDefaults.ephemeral()
        defaults.set(lateEvening.timeIntervalSince1970, forKey: MockTime.startKey)
        XCTAssertEqual(MockTime.read(from: defaults), MockTimeSetting(start: lateEvening, setAt: MockTime.processStart))
    }

    func testPresetsAreTheCasesGrigorNamed() {
        XCTAssertEqual(MockTimePreset.allCases.map { "\($0.hour):\($0.minute)" }, ["5:0", "23:45", "23:58"])
    }
}
