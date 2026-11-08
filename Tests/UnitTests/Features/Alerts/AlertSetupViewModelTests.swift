import XCTest
@testable import TrainTimes

/// Alert setup (TT-142): copy for This trip and Repeat, permission asked only on the first "Enable alerts", the rule's
/// states, and duplicates updating the existing rule.
@MainActor
final class AlertSetupViewModelTests: XCTestCase {
    private let formatter = TimeFormatter(format: .twelveHour)

    func testNewThisTripSheet() {
        let model = AlertSetupViewModel(request: Self.request(), rules: AlertFixtures.rules(FakeAlertServer()))
        XCTAssertEqual(model.title, "Alert for this train")
        XCTAssertEqual(model.routeName, "Oakville to Union")
        XCTAssertEqual(model.tripLine(formatter), "7:32 AM train · Thu, Nov 5")
        XCTAssertEqual(model.buttonTitle, "Enable alerts")
        XCTAssertEqual(model.footnote, "No account needed. Notification permission is requested after enabling.")
        XCTAssertNil(model.state)
        XCTAssertFalse(model.isManaging)
        XCTAssertTrue(model.canSave)
    }

    func testRepeatDays() {
        let model = AlertSetupViewModel(request: Self.request(.repeating), rules: AlertFixtures.rules(FakeAlertServer()))
        XCTAssertEqual(model.weekdays, [1, 2, 3, 4, 5])
        XCTAssertEqual(model.tripLine(formatter), "Usual 7:32 AM train · Mon to Fri")
        XCTAssertEqual(model.footnote, "A return train is a separate rule.")

        model.toggle(6)
        XCTAssertEqual(model.tripLine(formatter), "Usual 7:32 AM train · Mon to Sat")
        model.toggle(7)
        XCTAssertEqual(model.tripLine(formatter), "Usual 7:32 AM train · Every day")
        XCTAssertEqual(AlertSetupViewModel.summary(of: [6, 7]), "Sat, Sun")
        XCTAssertEqual(AlertSetupViewModel.summary(of: [1, 3, 5]), "Mon, Wed, Fri")

        for day in 1...7 { model.toggle(day) }
        XCTAssertEqual(model.tripLine(formatter), "Usual 7:32 AM train")
        XCTAssertFalse(model.canSave)
    }

    func testEnableAsksPermissionOnceThenOn() async {
        let server = FakeAlertServer()
        let permission = AskingPermission(answer: .allowed)
        let model = AlertSetupViewModel(request: Self.request(), rules: Self.rules(server, permission))

        await model.save()
        XCTAssertEqual(model.state, .on)
        XCTAssertEqual(model.title, "Manage alert")
        XCTAssertEqual(model.buttonTitle, "Save")
        let requests = await permission.requests
        XCTAssertEqual(requests, 1)

        // Saving again updates the same rule and does not ask again.
        await model.save()
        let saved = await server.saved
        XCTAssertEqual(saved.count, 2)
        XCTAssertEqual(saved[0].id, saved[1].id)
        let requestsAfter = await permission.requests
        XCTAssertEqual(requestsAfter, 1)
    }

    /// TT-153: launch and coming back to the app read the permission but never show the iOS dialog; only Enable alerts
    /// asks, so a new rider reaches the timeline with no prompt.
    func testLaunchAndForegroundNeverAsk() async {
        let permission = AskingPermission(answer: .allowed)
        let rules = Self.rules(FakeAlertServer(), permission)
        await rules.refresh()
        await rules.refreshPermission()
        let requests = await permission.requests
        XCTAssertEqual(requests, 0)
        XCTAssertEqual(rules.permission, .notAsked)
    }

    func testDeniedPermissionShowsNotificationsOffNeverOn() async {
        let server = FakeAlertServer()
        let model = AlertSetupViewModel(request: Self.request(), rules: Self.rules(server, AskingPermission(answer: .off)))

        await model.save()
        XCTAssertEqual(model.state, .notificationsOff)
        XCTAssertTrue(model.isManaging)
        // The rule is still saved, so allowing notifications later needs no new save.
        let saved = await server.saved
        XCTAssertEqual(saved.count, 1)
    }

    func testSettingUpWhileSavingAndRepeatedTapsSendOneRequest() async {
        let server = FakeAlertServer()
        await server.holdSaves()
        let model = AlertSetupViewModel(request: Self.request(), rules: AlertFixtures.rules(server))

        let first = Task { await model.save() }
        await server.waitUntilHolding()
        XCTAssertEqual(model.state, .settingUp)
        XCTAssertFalse(model.canSave)
        // A new alert keeps its first title and button while it sets up, as in permission-prompt.png.
        XCTAssertEqual(model.title, "Alert for this train")
        XCTAssertEqual(model.buttonTitle, "Enable alerts")
        await model.save()

        await server.release()
        await first.value
        XCTAssertEqual(model.state, .on)
        let saved = await server.saved
        XCTAssertEqual(saved.count, 1)
    }

    func testCouldNotSaveKeepsRuleAndRetries() async {
        let server = FakeAlertServer()
        await server.setFailing(true)
        let rules = AlertFixtures.rules(server)
        let model = AlertSetupViewModel(request: Self.request(), rules: rules)

        await model.save()
        XCTAssertEqual(model.state, .couldNotSave)
        XCTAssertEqual(rules.rules.count, 1)
        let id = rules.rules.first?.id

        await server.setFailing(false)
        await model.save()
        XCTAssertEqual(model.state, .on)
        XCTAssertEqual(rules.rules.map(\.id), [id].compactMap { $0 })
    }

    func testThisTripAndRepeatAreSeparateRules() async {
        let rules = AlertFixtures.rules(FakeAlertServer())
        let model = AlertSetupViewModel(request: Self.request(), rules: rules)
        await model.save()

        model.kind = .repeating
        XCTAssertFalse(model.isManaging)
        XCTAssertEqual(model.title, "Alert for this train")
        await model.save()
        XCTAssertEqual(rules.rules.count, 2)

        model.kind = .thisTrip
        XCTAssertTrue(model.isManaging)
    }

    func testSameUsualTrainOnAnotherDayUpdatesTheRepeatRule() async {
        let rules = AlertFixtures.rules(FakeAlertServer())
        let thursday = AlertSetupViewModel(request: Self.request(.repeating), rules: rules)
        thursday.toggle(5)
        await thursday.save()

        let friday = AlertSetupViewModel(
            request: AlertSetupRequest(route: AlertFixtures.route, trip: AlertFixtures.trip("LW-0732-20261106", day: 6), kind: .repeating),
            rules: rules
        )
        XCTAssertTrue(friday.isManaging)
        XCTAssertEqual(friday.weekdays, [1, 2, 3, 4])
        friday.toggle(5)
        await friday.save()
        XCTAssertEqual(rules.rules.count, 1)
        XCTAssertEqual(rules.rules.first?.weekdays, [1, 2, 3, 4, 5])
    }

    func testDeleteRemovesTheRule() async {
        let server = FakeAlertServer()
        let rules = AlertFixtures.rules(server)
        let model = AlertSetupViewModel(request: Self.request(), rules: rules)
        await model.save()
        let id = rules.rules.first?.id

        await model.delete()
        XCTAssertTrue(rules.rules.isEmpty)
        XCTAssertFalse(model.isManaging)
        let deleted = await server.deleted
        XCTAssertEqual(deleted, [id].compactMap { $0 })
    }

    // MARK: Helpers

    static func request(_ kind: AlertRule.Kind = .thisTrip) -> AlertSetupRequest {
        AlertSetupRequest(route: AlertFixtures.route, trip: AlertFixtures.trip(), kind: kind)
    }

    static func rules(_ server: FakeAlertServer, _ permission: any NotificationPermissionProviding) -> AlertRules {
        AlertRules(server: server, push: FixturePushRegistration(), permissions: permission, defaults: nil)
    }
}

/// Not asked until the app asks; then the rider's answer, as the iOS dialog gives it. Counts the requests.
actor AskingPermission: NotificationPermissionProviding {
    private var value = NotificationPermission.notAsked
    private let answer: NotificationPermission
    private(set) var requests = 0

    init(answer: NotificationPermission) {
        self.answer = answer
    }

    func current() async -> NotificationPermission { value }

    func request() async -> NotificationPermission {
        requests += 1
        if value == .notAsked { value = answer }
        return value
    }
}
