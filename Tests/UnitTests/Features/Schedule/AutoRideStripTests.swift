import XCTest
@testable import TrainTimes

/// The automatic ride's one-time strip (TT-243, D120): due at the first ride that started by itself, shown once that ride is
/// over while Automatic ride reads on, until OK or Turn off; its place in the ride strip's slot.
@MainActor
final class AutoRideStripTests: XCTestCase {
    private var recorder: RecordingAnalytics!

    private final class Setting {
        var readsOn = false
    }

    override func setUp() async throws {
        try await super.setUp()
        recorder = RecordingAnalytics.install()
    }

    override func tearDown() async throws {
        Analytics.tracker = nil
        try await super.tearDown()
    }

    private func strip(
        _ store: AutoRideStore?, readsOn: @escaping @MainActor () -> Bool = { true }, haptics: FakeHaptics = FakeHaptics()
    ) -> AutoRideStrip {
        AutoRideStrip(store: store, readsOn: readsOn, haptics: haptics)
    }

    func testNotShownUntilARideStartedByItself() {
        let store = AutoRideStore(defaults: .ephemeral())
        let strip = strip(store)
        XCTAssertFalse(strip.isShown)

        store.stripDue = true
        strip.refresh()
        XCTAssertTrue(strip.isShown)
    }

    func testOKClosesItForGood() {
        let store = AutoRideStore(defaults: .ephemeral())
        store.stripDue = true
        let haptics = FakeHaptics()
        let strip = strip(store, haptics: haptics)

        strip.ok()

        XCTAssertFalse(strip.isShown)
        XCTAssertTrue(store.stripAnswered)
        XCTAssertFalse(store.isOff)
        XCTAssertEqual(haptics.played, [.tap])
        XCTAssertTrue(recorder.events.isEmpty)
        XCTAssertFalse(self.strip(store).isShown, "Not again after a relaunch")
    }

    func testTurnOffStoresTheOffAndSaysSo() {
        let store = AutoRideStore(defaults: .ephemeral())
        store.stripDue = true
        let haptics = FakeHaptics()
        let strip = strip(store, haptics: haptics)

        strip.turnOff()

        XCTAssertFalse(strip.isShown)
        XCTAssertTrue(store.isOff)
        XCTAssertTrue(store.stripAnswered)
        XCTAssertNil(store.turnedOffAt, "The rider's own off: Settings shows the plain note")
        XCTAssertEqual(haptics.played, [.tap])
        XCTAssertEqual(recorder.events, [.settingChanged("auto_ride", value: "off")])
    }

    func testHiddenWhileAutomaticRideReadsOff() {
        let store = AutoRideStore(defaults: .ephemeral())
        store.stripDue = true
        let setting = Setting()
        let strip = strip(store, readsOn: { setting.readsOn })
        XCTAssertFalse(strip.isShown)

        setting.readsOn = true
        strip.refresh()
        XCTAssertTrue(strip.isShown, "Still due: it was never answered")
    }

    func testNoStoreNeverShowsIt() {
        XCTAssertFalse(strip(nil).isShown)
    }

    /// Riding and the departure question come first in the slot; Automatic direction's strip after it.
    func testItsPlaceInTheRideStripsSlot() {
        XCTAssertEqual(
            RideStripContent(isRiding: true, asksDeparture: false, showsAutoRideStrip: true, showsDirectionStrip: true), .riding
        )
        XCTAssertEqual(
            RideStripContent(isRiding: false, asksDeparture: true, showsAutoRideStrip: true, showsDirectionStrip: true), .asking
        )
        XCTAssertEqual(
            RideStripContent(isRiding: false, asksDeparture: false, showsAutoRideStrip: true, showsDirectionStrip: true), .autoRide
        )
        XCTAssertEqual(
            RideStripContent(isRiding: false, asksDeparture: false, showsAutoRideStrip: false, showsDirectionStrip: true), .direction
        )
    }
}
