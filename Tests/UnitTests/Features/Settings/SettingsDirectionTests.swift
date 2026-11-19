import Observation
import UIKit
import XCTest
@testable import TrainTimes

/// Settings › Automatic direction (TT-234, D116): what the switch reads for each location permission, what a tap does in
/// each, the rider's stored "off" and `setting_changed`; and the Testing page's Demo place and Last look.
@MainActor
final class SettingsDirectionTests: XCTestCase {
    private var recorder: RecordingAnalytics!
    /// The pages of the Settings app the model opened; a test opens nothing.
    private var opened: [URL] = []

    private let plainNote = "settings.auto_direction.note"
    private let route = AlertFixtures.route

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
        _ location: (any DirectionLocating)?, store: DirectionStore?, look: DirectionLook? = nil, route: Route? = nil,
        defaults: UserDefaults = .ephemeral()
    ) -> SettingsViewModel {
        SettingsViewModel(
            settings: AppSettings(defaults: .ephemeral()), permissions: FakeNotificationPermission(.allowed),
            appInfo: AppInfo(version: "1.0", build: "1"), showsTesting: true, direction: location, directionStore: store,
            look: look, route: { route }, defaults: defaults, openSettings: { [weak self] page in self?.opened.append(page) }
        )
    }

    // MARK: The switch

    /// Location allowed with Precise Location reads on with nothing stored: an install that already allowed location,
    /// and a rider who allows it for a ride.
    func testReadsOnWithLocationAllowedAndPreciseLocation() {
        let store = DirectionStore(defaults: nil)
        let model = makeModel(FakeDirectionLocation(), store: store)
        XCTAssertTrue(model.autoDirection)
        XCTAssertEqual(model.autoDirectionNote, plainNote)
        XCTAssertFalse(store.isOff)
        XCTAssertTrue(recorder.events.isEmpty, "reading the switch sends nothing")
    }

    /// Off stores the rider's "off", on clears it: only the "off" is ever stored. Each tap that changes the switch sends
    /// `setting_changed` once, with the setting and the value and nothing else.
    func testOffStoresTheRidersOffAndOnClearsIt() {
        let location = FakeDirectionLocation()
        let defaults = UserDefaults.ephemeral()
        let store = DirectionStore(defaults: defaults)
        let model = makeModel(location, store: store)

        // The switch's binding is the tap.
        model.autoDirection = false
        XCTAssertFalse(model.autoDirection)
        XCTAssertTrue(store.isOff)
        XCTAssertEqual(defaults.object(forKey: DirectionStore.offKey) as? Bool, true)
        XCTAssertEqual(model.autoDirectionNote, plainNote, "the rider's own off needs nothing from iOS")
        XCTAssertEqual(recorder.events, [.settingChanged("auto_direction", value: "off")])
        XCTAssertEqual(recorder.events.first?.properties, ["setting": .string("auto_direction"), "value": .string("off")])

        XCTAssertNil(model.tapAutoDirection(true), "no prompt: location is allowed")
        XCTAssertTrue(model.autoDirection)
        XCTAssertFalse(store.isOff)
        XCTAssertNil(defaults.object(forKey: DirectionStore.offKey), "nothing is stored for on")
        XCTAssertEqual(
            recorder.events, [.settingChanged("auto_direction", value: "off"), .settingChanged("auto_direction", value: "on")]
        )
        XCTAssertEqual(location.requests, 0)
        XCTAssertTrue(opened.isEmpty)
    }

    /// The stored "off" reads off at the next launch, whatever iOS allows, with the plain note.
    func testTheStoredOffReadsOffAtTheNextLaunch() {
        let defaults = UserDefaults.ephemeral()
        DirectionStore(defaults: defaults).isOff = true
        let model = makeModel(FakeDirectionLocation(), store: DirectionStore(defaults: defaults))
        XCTAssertFalse(model.autoDirection)
        XCTAssertEqual(model.autoDirectionNote, plainNote)
        XCTAssertTrue(recorder.events.isEmpty)
    }

    /// Location never asked, or Allow Once ran out: the switch reads off, and turning it on shows the iOS prompt at once.
    /// Allowed there, it reads on, and an "off" stored earlier is gone.
    func testNotAskedShowsTheIOSPromptAndReadsOnWhenAllowed() async throws {
        let location = FakeDirectionLocation(permission: .notAsked)
        let store = DirectionStore(defaults: nil)
        store.isOff = true
        let model = makeModel(location, store: store)
        XCTAssertFalse(model.autoDirection)
        XCTAssertEqual(model.autoDirectionNote, plainNote)

        let prompt = try XCTUnwrap(model.tapAutoDirection(true))
        await prompt.value
        XCTAssertEqual(location.requests, 1)
        XCTAssertTrue(model.autoDirection)
        XCTAssertFalse(store.isOff)
        XCTAssertEqual(recorder.events, [.settingChanged("auto_direction", value: "on")])
        XCTAssertTrue(opened.isEmpty, "the prompt, no page of the Settings app")
    }

    /// Don't Allow in the prompt: the switch stays off, nothing is sent, and the note says what is needed.
    func testARefusedPromptLeavesItOffAndSendsNothing() async throws {
        let location = FakeDirectionLocation(permission: .notAsked)
        location.answer = .refused
        let model = makeModel(location, store: DirectionStore(defaults: nil))

        let prompt = try XCTUnwrap(model.tapAutoDirection(true))
        await prompt.value
        XCTAssertEqual(location.requests, 1)
        XCTAssertFalse(model.autoDirection)
        XCTAssertEqual(model.autoDirectionNote, "settings.auto_direction.needs_location")
        XCTAssertTrue(recorder.events.isEmpty, "iOS refused: the switch did not change")
        XCTAssertTrue(opened.isEmpty)
    }

    /// Allowed in the prompt with Precise Location switched off there: still off, nothing sent, the note asks for it.
    func testAPromptAllowedWithoutPreciseLocationStaysOff() async throws {
        let location = FakeDirectionLocation(permission: .notAsked, isPrecise: false)
        let model = makeModel(location, store: DirectionStore(defaults: nil))

        let prompt = try XCTUnwrap(model.tapAutoDirection(true))
        await prompt.value
        XCTAssertEqual(location.permission, .allowed)
        XCTAssertFalse(model.autoDirection)
        XCTAssertEqual(model.autoDirectionNote, "settings.auto_direction.needs_precise")
        XCTAssertTrue(recorder.events.isEmpty)
        XCTAssertTrue(opened.isEmpty)
    }

    /// Location refused: the note says so, and a tap opens the app's page in the Settings app, never the prompt. The
    /// switch stays off and nothing is sent. Back with location allowed it reads on, still with no event: the permission
    /// changed it, not a tap.
    func testRefusedOpensTheSettingsAppAndStaysOff() async {
        let location = FakeDirectionLocation(permission: .refused)
        let model = makeModel(location, store: DirectionStore(defaults: nil))
        XCTAssertFalse(model.autoDirection)
        XCTAssertEqual(model.autoDirectionNote, "settings.auto_direction.needs_location")

        XCTAssertNil(model.tapAutoDirection(true))
        XCTAssertEqual(opened, [SettingsViewModel.locationSettingsURL])
        XCTAssertEqual(opened.first?.absoluteString, UIApplication.openSettingsURLString)
        XCTAssertEqual(location.requests, 0)
        XCTAssertFalse(model.autoDirection)
        XCTAssertTrue(recorder.events.isEmpty, "the tap only opened the Settings app")

        location.permission = .allowed
        await model.refreshPermission()
        XCTAssertTrue(model.autoDirection)
        XCTAssertEqual(model.autoDirectionNote, plainNote)
        XCTAssertTrue(recorder.events.isEmpty)
    }

    /// Location allowed with Precise Location off: the same, with its own note.
    func testPreciseLocationOffOpensTheSettingsAppAndStaysOff() async {
        let location = FakeDirectionLocation(isPrecise: false)
        let model = makeModel(location, store: DirectionStore(defaults: nil))
        XCTAssertFalse(model.autoDirection)
        XCTAssertEqual(model.autoDirectionNote, "settings.auto_direction.needs_precise")

        XCTAssertNil(model.tapAutoDirection(true))
        XCTAssertEqual(opened, [SettingsViewModel.locationSettingsURL])
        XCTAssertEqual(location.requests, 0)
        XCTAssertFalse(model.autoDirection)
        XCTAssertTrue(recorder.events.isEmpty)

        location.isPrecise = true
        await model.refreshPermission()
        XCTAssertTrue(model.autoDirection)
        XCTAssertEqual(model.autoDirectionNote, plainNote)
        XCTAssertTrue(recorder.events.isEmpty)
    }

    /// An "off" stored before location was refused goes with the tap that opens the Settings app: the rider asked for on,
    /// so allowing location there is enough.
    func testATapForOnClearsAnOldOffThoughIOSKeepsItOff() async {
        let location = FakeDirectionLocation(permission: .refused)
        let store = DirectionStore(defaults: nil)
        store.isOff = true
        let model = makeModel(location, store: store)

        model.tapAutoDirection(true)
        XCTAssertFalse(store.isOff)
        XCTAssertFalse(model.autoDirection)
        location.permission = .allowed
        await model.refreshPermission()
        XCTAssertTrue(model.autoDirection)
        XCTAssertTrue(recorder.events.isEmpty)
    }

    /// No reader or no store (previews), and the reader of fixture runs and the unit test host: the row still shows, reads
    /// off, and a tap does nothing.
    func testWithoutALocationReaderItReadsOffAndATapDoesNothing() {
        let unavailable = FakeDirectionLocation(permission: .unavailable)
        let store = DirectionStore(defaults: nil)
        let models = [
            makeModel(nil, store: store), makeModel(FakeDirectionLocation(), store: nil), makeModel(unavailable, store: store),
            makeModel(NoDirectionLocation(), store: store),
        ]
        for model in models {
            XCTAssertFalse(model.autoDirection)
            XCTAssertEqual(model.autoDirectionNote, plainNote)
            XCTAssertNil(model.tapAutoDirection(true))
            XCTAssertNil(model.tapAutoDirection(false))
            XCTAssertFalse(model.autoDirection)
        }
        XCTAssertEqual(unavailable.requests, 0)
        XCTAssertFalse(store.isOff)
        XCTAssertTrue(opened.isEmpty)
        XCTAssertTrue(recorder.events.isEmpty)
    }

    /// The reader is not observed, so reading the permission again (Settings appears, the app comes back from the
    /// Settings app) has the switch drawn again.
    func testReadingThePermissionAgainRedrawsTheSwitch() async {
        let location = FakeDirectionLocation(permission: .refused)
        let model = makeModel(location, store: DirectionStore(defaults: nil))
        let redrawn = expectation(description: "the switch is read again")
        withObservationTracking {
            _ = model.autoDirection
        } onChange: {
            redrawn.fulfill()
        }
        location.permission = .allowed
        await model.refreshPermission()
        await fulfillment(of: [redrawn], timeout: 1)
        XCTAssertTrue(model.autoDirection)
    }

    // MARK: Testing › Demo place

    /// Off, or one of the route's two stations by id, stored under `DemoPlace.key`; the switch names them by their short
    /// names. It joins the Testing row's value and Reset.
    func testDemoPlaceIsOneOfTheRoutesStationsAndResetTurnsItOff() {
        let defaults = UserDefaults.ephemeral()
        let model = makeModel(nil, store: nil, route: route, defaults: defaults)
        XCTAssertEqual(
            model.demoPlaceStations, [DemoPlaceStation(id: "OA", name: "Oakville"), DemoPlaceStation(id: "UN", name: "Union")]
        )
        XCTAssertNil(model.demoPlace)
        XCTAssertFalse(model.isTestingActive)
        XCTAssertEqual(model.testingValue, "Off")

        model.demoPlace = "UN"
        XCTAssertEqual(model.demoPlace, "UN")
        XCTAssertEqual(defaults.string(forKey: DemoPlace.key), "UN")
        XCTAssertEqual(DemoPlace.key, "settings.demoPlace", "the launch argument's name")
        XCTAssertTrue(model.isTestingActive)
        XCTAssertEqual(model.testingValue, "Demo place")
        let relaunched = makeModel(nil, store: nil, route: route, defaults: defaults)
        XCTAssertEqual(relaunched.demoPlace, "UN", "read back at the next launch")

        model.demoTrains = .delays
        model.isMockTimeOn = true
        XCTAssertEqual(model.testingValue, "Delays · Demo place · Mock time")

        model.resetTesting()
        XCTAssertNil(model.demoPlace)
        XCTAssertNil(defaults.object(forKey: DemoPlace.key))
        XCTAssertFalse(model.isTestingActive)
        XCTAssertEqual(model.testingValue, "Off")
    }

    /// Long names are shortened as on the capsule: "Oakville GO" is "Oakville", "Union Station" is "Union".
    func testDemoPlaceShowsShortStationNames() {
        let long = Route(from: Station(id: "OA", name: "Oakville GO"), to: Station(id: "UN", name: "Union Station"), line: nil)
        let model = makeModel(nil, store: nil, route: long)
        XCTAssertEqual(model.demoPlaceStations.map(\.name), ["Oakville", "Union"])
        XCTAssertTrue(makeModel(nil, store: nil).demoPlaceStations.isEmpty, "no route, no stations")
    }

    /// A stored id that is neither of the route's two stations reads Off, and so does any id with no route.
    func testADemoPlaceThatIsNeitherStationReadsOff() {
        let defaults = UserDefaults.ephemeral()
        defaults.set("CL", forKey: DemoPlace.key)
        let model = makeModel(nil, store: nil, route: route, defaults: defaults)
        XCTAssertNil(model.demoPlace)
        XCTAssertFalse(model.isTestingActive)
        XCTAssertEqual(model.testingValue, "Off")

        // Reset still clears what is stored.
        model.resetTesting()
        XCTAssertNil(defaults.object(forKey: DemoPlace.key))

        defaults.set("UN", forKey: DemoPlace.key)
        XCTAssertNil(makeModel(nil, store: nil, defaults: defaults).demoPlace, "no route")
        XCTAssertEqual(makeModel(nil, store: nil, route: route, defaults: defaults).demoPlace, "UN")
    }

    /// A demo place counts as location allowed, so choosing one has the Automatic direction switch drawn again.
    func testChoosingADemoPlaceRedrawsTheSwitch() async {
        let model = makeModel(FakeDirectionLocation(permission: .refused), store: DirectionStore(defaults: nil), route: route)
        let redrawn = expectation(description: "the switch is read again")
        withObservationTracking {
            _ = model.autoDirection
        } onChange: {
            redrawn.fulfill()
        }
        model.demoPlace = "OA"
        await fulfillment(of: [redrawn], timeout: 1)
    }

    // MARK: Testing › Last look

    /// The seconds the look waited, with one decimal, and what it did; never a place.
    func testLastLookSaysHowLongItWaitedAndWhatItDid() {
        XCTAssertEqual(SettingsViewModel.lastLookText(nil), "None yet")
        XCTAssertEqual(
            SettingsViewModel.lastLookText(DirectionLook.LastLook(waited: 0.44, outcome: .turn)), "Turned the route after 0.4 s"
        )
        XCTAssertEqual(SettingsViewModel.lastLookText(DirectionLook.LastLook(waited: 3.26, outcome: .ask)), "Asked after 3.3 s")
        XCTAssertEqual(
            SettingsViewModel.lastLookText(DirectionLook.LastLook(waited: 10, outcome: .nothing(.noReading))),
            "Nothing after 10.0 s: no clear reading in 10 s"
        )
        XCTAssertEqual(
            SettingsViewModel.lastLookText(DirectionLook.LastLook(waited: 0, outcome: .nothing(.alreadyCloser))),
            "Nothing after 0.0 s: already at the closer station"
        )
        // A reading in between the two stations, or far from both, ends the look at once.
        XCTAssertEqual(
            SettingsViewModel.lastLookText(DirectionLook.LastLook(waited: 0.2, outcome: .nothing(.inBetween))),
            "Nothing after 0.2 s: between the stations or far from both"
        )
    }

    /// Every reason a look ends with nothing has its words in the strings file.
    func testEveryReasonHasItsWords() {
        let reasons: [DirectionRule.Reason] = [
            .alreadyCloser, .inBetween, .noReading, .covered, .noPlaces, .left, .off, .riding, .chosenByHand, .chosenByLink,
            .undone, .noRoute, .restarted, .rideProof,
        ]
        for reason in reasons {
            let text = SettingsViewModel.lastLookText(DirectionLook.LastLook(waited: 1, outcome: .nothing(reason)))
            XCTAssertTrue(text.hasPrefix("Nothing after 1.0 s: "), text)
            XCTAssertFalse(text.contains("settings.last_look"), "\(reason.rawValue) has no string")
        }
    }

    /// The page shows the look's own last result: none yet, then a look that could not start because location is refused.
    func testTheModelReadsTheLooksLastResult() {
        let location = FakeDirectionLocation(permission: .refused)
        let store = DirectionStore(defaults: nil)
        let look = DirectionLook(
            schedule: FakeRouteTurning(route: route), location: location, stations: DirectionFixtures.stations, store: store,
            clock: FixedClock(now: Date(timeIntervalSince1970: 1_795_107_600))
        )
        let model = makeModel(location, store: store, look: look, route: route)
        XCTAssertEqual(model.lastLookText, "None yet")
        XCTAssertEqual(makeModel(location, store: store).lastLookText, "None yet", "no look at all")

        look.update(DirectionLook.Scene(isActive: true, isInFront: true))
        XCTAssertEqual(model.lastLookText, "Nothing after 0.0 s: Automatic direction is off")
    }
}
