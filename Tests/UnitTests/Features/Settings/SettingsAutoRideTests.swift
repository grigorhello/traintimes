import XCTest
@testable import TrainTimes

/// Settings › Automatic ride and When the app is closed (TT-243, D120): on by default with location and Precise Location,
/// only the rider's "off" stored, the prompts and the Settings app where iOS cannot ask, the Automatic card's one note, and
/// `setting_changed` only when a tap changed a switch.
@MainActor
final class SettingsAutoRideTests: XCTestCase {
    private var recorder: RecordingAnalytics!
    /// The pages of the Settings app the model opened; a test opens nothing.
    private var opened: [URL] = []

    override func setUp() async throws {
        try await super.setUp()
        recorder = RecordingAnalytics.install()
        opened = []
    }

    override func tearDown() async throws {
        Analytics.tracker = nil
        try await super.tearDown()
    }

    private func makeModel(
        _ location: (any DirectionLocating)?, store: AutoRideStore?, wake: AutoRideWake? = nil, strip: AutoRideStrip? = nil,
        settings: AppSettings = AppSettings(defaults: .ephemeral())
    ) -> SettingsViewModel {
        SettingsViewModel(
            settings: settings, permissions: FakeNotificationPermission(.allowed), appInfo: AppInfo(version: "1.0", build: "1"),
            showsTesting: true, autoRideStore: store, autoRideWake: wake, autoRideStrip: strip, haptics: FakeHaptics(),
            direction: location, directionStore: DirectionStore(defaults: nil), defaults: .ephemeral(),
            openSettings: { [weak self] page in self?.opened.append(page) }
        )
    }

    private var events: [AnalyticsEvent] { recorder.events.filter { $0.name == "setting_changed" } }

    // MARK: Automatic ride

    func testReadsOnByDefaultWithLocationAndPreciseLocation() {
        let store = AutoRideStore(defaults: .ephemeral())
        let model = makeModel(FakeDirectionLocation(), store: store)
        XCTAssertTrue(model.autoRide)
        XCTAssertFalse(store.isOff)
        XCTAssertEqual(model.automaticNote, "settings.automatic.note")
        XCTAssertTrue(recorder.events.isEmpty, "Reading the switch sends nothing")
    }

    func testOffIsTheOnlyThingStored() {
        let defaults = UserDefaults.ephemeral()
        let model = makeModel(FakeDirectionLocation(), store: AutoRideStore(defaults: defaults))

        model.tapAutoRide(false)

        XCTAssertFalse(model.autoRide)
        XCTAssertTrue(AutoRideStore(defaults: defaults).isOff)
        XCTAssertEqual(events, [.settingChanged("auto_ride", value: "off")])
        XCTAssertEqual(model.automaticNote, "settings.automatic.note", "The rider's own off needs no note")

        model.tapAutoRide(true)

        XCTAssertTrue(model.autoRide)
        XCTAssertFalse(AutoRideStore(defaults: defaults).isOff)
        XCTAssertEqual(events, [.settingChanged("auto_ride", value: "off"), .settingChanged("auto_ride", value: "on")])
        XCTAssertTrue(opened.isEmpty)
    }

    func testLocationNeverAskedShowsThePromptAtOnce() async {
        let location = FakeDirectionLocation(permission: .notAsked)
        let model = makeModel(location, store: AutoRideStore(defaults: .ephemeral()))
        XCTAssertFalse(model.autoRide)

        await model.tapAutoRide(true)?.value

        XCTAssertEqual(location.requests, 1)
        XCTAssertTrue(model.autoRide)
        XCTAssertEqual(events, [.settingChanged("auto_ride", value: "on")])
    }

    func testARefusedPromptLeavesItOffAndSendsNothing() async {
        let location = FakeDirectionLocation(permission: .notAsked)
        location.answer = .refused
        let model = makeModel(location, store: AutoRideStore(defaults: .ephemeral()))

        await model.tapAutoRide(true)?.value

        XCTAssertFalse(model.autoRide)
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(model.automaticNote, "settings.auto_direction.needs_location")
    }

    func testLocationRefusedOpensTheSettingsApp() {
        let model = makeModel(FakeDirectionLocation(permission: .refused), store: AutoRideStore(defaults: .ephemeral()))
        XCTAssertNil(model.tapAutoRide(true))
        XCTAssertEqual(opened, [SettingsViewModel.locationSettingsURL])
        XCTAssertFalse(model.autoRide)
        XCTAssertTrue(events.isEmpty)
    }

    func testPreciseLocationOffOpensTheSettingsApp() {
        let model = makeModel(FakeDirectionLocation(isPrecise: false), store: AutoRideStore(defaults: .ephemeral()))
        XCTAssertFalse(model.autoRide)
        XCTAssertEqual(model.automaticNote, "settings.auto_direction.needs_precise")

        model.tapAutoRide(true)

        XCTAssertEqual(opened, [SettingsViewModel.locationSettingsURL])
        XCTAssertFalse(model.autoRide)
    }

    func testTurningItOffAnswersADueStrip() {
        let store = AutoRideStore(defaults: .ephemeral())
        store.stripDue = true
        let model = makeModel(FakeDirectionLocation(), store: store)

        model.tapAutoRide(false)

        XCTAssertTrue(store.stripAnswered)
    }

    func testTwoNotOnItShowTheirNoteUntilTurnedOnAgain() {
        let store = AutoRideStore(defaults: .ephemeral())
        store.recordNotOnIt(at: Date(timeIntervalSince1970: 1_795_000_000))
        store.recordNotOnIt(at: Date(timeIntervalSince1970: 1_795_000_600))
        let model = makeModel(FakeDirectionLocation(), store: store)
        XCTAssertFalse(model.autoRide)
        XCTAssertEqual(model.automaticNote, "settings.auto_ride.turned_off")

        model.tapAutoRide(true)

        XCTAssertTrue(model.autoRide)
        XCTAssertNil(store.turnedOffAt)
        XCTAssertEqual(model.automaticNote, "settings.automatic.note")
    }

    /// Location refused says so before the two Not on it do: the rider has to fix that first.
    func testTheNotesOrder() {
        let store = AutoRideStore(defaults: .ephemeral())
        store.recordNotOnIt(at: Date(timeIntervalSince1970: 1_795_000_000))
        store.recordNotOnIt(at: Date(timeIntervalSince1970: 1_795_000_600))
        XCTAssertEqual(
            makeModel(FakeDirectionLocation(permission: .refused), store: store).automaticNote,
            "settings.auto_direction.needs_location"
        )
        XCTAssertEqual(
            makeModel(FakeDirectionLocation(isPrecise: false), store: store).automaticNote, "settings.auto_direction.needs_precise"
        )
        XCTAssertEqual(makeModel(FakeDirectionLocation(), store: store).automaticNote, "settings.auto_ride.turned_off")
    }

    func testADemoModeReadsOnWithNoLocation() {
        let settings = AppSettings(defaults: .ephemeral())
        settings.demoAutoRide = .boards
        let model = makeModel(FakeDirectionLocation(permission: .unavailable), store: AutoRideStore(defaults: .ephemeral()), settings: settings)
        XCTAssertTrue(model.autoRide)

        model.tapAutoRide(false)
        model.tapAutoRide(true)

        XCTAssertTrue(model.autoRide)
        XCTAssertTrue(opened.isEmpty, "The demo needs no location")
    }

    func testTheStripFollowsTheSwitch() {
        let store = AutoRideStore(defaults: .ephemeral())
        store.stripDue = true
        let location = FakeDirectionLocation()
        let strip = AutoRideStrip(store: store, readsOn: { location.readsOn(store) }, haptics: FakeHaptics())
        let model = makeModel(location, store: store, strip: strip)
        XCTAssertTrue(strip.isShown)

        model.tapAutoRide(false)

        XCTAssertFalse(strip.isShown)
    }

    // MARK: When the app is closed

    func testWhenTheAppIsClosedShowsOnlyWhileAutomaticRideReadsOn() {
        let store = AutoRideStore(defaults: .ephemeral())
        let wake = AutoRideWake.switchOnly(location: FakeWakeLocation(allowsAlways: true), store: store)
        let model = makeModel(FakeDirectionLocation(), store: store, wake: wake)
        XCTAssertTrue(model.showsAutoRideClosed)
        XCTAssertFalse(model.autoRideClosed, "Off by default")

        model.tapAutoRide(false)
        XCTAssertFalse(model.showsAutoRideClosed)

        XCTAssertFalse(makeModel(FakeDirectionLocation(), store: store).showsAutoRideClosed, "Not in fixture runs")
    }

    func testOnWithAlwaysAllowedReadsOnAtOnce() {
        let store = AutoRideStore(defaults: .ephemeral())
        let location = FakeWakeLocation(allowsAlways: true)
        let wake = AutoRideWake.switchOnly(location: location, store: store)
        let model = makeModel(FakeDirectionLocation(), store: store, wake: wake)

        XCTAssertNil(model.tapAutoRideClosed(true))

        XCTAssertTrue(model.autoRideClosed)
        XCTAssertTrue(store.closed)
        XCTAssertTrue(location.isWaking)
        XCTAssertTrue(location.asks.isEmpty)
        XCTAssertEqual(events, [.settingChanged("auto_ride_closed", value: "on")])

        model.tapAutoRideClosed(false)

        XCTAssertFalse(model.autoRideClosed)
        XCTAssertFalse(store.closed)
        XCTAssertFalse(location.isWaking)
        XCTAssertEqual(events.last, .settingChanged("auto_ride_closed", value: "off"))
    }

    func testOnAsksWhenInUseThenAlways() async {
        let store = AutoRideStore(defaults: .ephemeral())
        let location = FakeWakeLocation(allowsAlways: false)
        location.canAskWhenInUse = true
        let wake = AutoRideWake.switchOnly(location: location, store: store)
        let model = makeModel(FakeDirectionLocation(), store: store, wake: wake)

        await model.tapAutoRideClosed(true)?.value

        XCTAssertEqual(location.asks, [.whenInUse, .always])
        XCTAssertTrue(model.autoRideClosed)
        XCTAssertEqual(events, [.settingChanged("auto_ride_closed", value: "on")])
    }

    func testAlwaysRefusedLeavesItOffAndTheNextTapOpensTheSettingsApp() async {
        let store = AutoRideStore(defaults: .ephemeral())
        let location = FakeWakeLocation(allowsAlways: false)
        location.answer = false
        let wake = AutoRideWake.switchOnly(location: location, store: store)
        let model = makeModel(FakeDirectionLocation(), store: store, wake: wake)

        await model.tapAutoRideClosed(true)?.value

        XCTAssertEqual(location.asks, [.always])
        XCTAssertFalse(model.autoRideClosed)
        XCTAssertTrue(events.isEmpty)

        // iOS shows its Always dialog once: from now on only the Settings app allows it.
        XCTAssertNil(model.tapAutoRideClosed(true))
        XCTAssertEqual(opened, [SettingsViewModel.locationSettingsURL])
        XCTAssertEqual(location.asks, [.always])
    }

    func testAlwaysTakenBackInTheSettingsAppReadsOff() {
        let store = AutoRideStore(defaults: .ephemeral())
        let location = FakeWakeLocation(allowsAlways: true)
        let wake = AutoRideWake.switchOnly(location: location, store: store)
        let model = makeModel(FakeDirectionLocation(), store: store, wake: wake)
        model.tapAutoRideClosed(true)
        XCTAssertTrue(model.autoRideClosed)

        location.allowsAlways = false
        wake.resume()

        XCTAssertFalse(model.autoRideClosed)
        XCTAssertFalse(location.isWaking)
        XCTAssertTrue(store.closed, "The rider's own on stays, for when Always comes back")
    }
}
