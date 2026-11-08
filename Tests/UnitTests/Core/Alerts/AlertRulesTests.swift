import XCTest
@testable import TrainTimes

/// The alert rules store (TT-141): Setting up until the server stored the rule and the token is registered, one request
/// per rule in flight, Could not save kept on device, Notifications off whatever the server says, and duplicates.
@MainActor
final class AlertRulesTests: XCTestCase {
    private let route = AlertFixtures.route

    func testSettingUpUntilTheServerStoresTheRuleThenOn() async {
        let server = FakeAlertServer()
        await server.holdSaves()
        let settings = AppSettings(defaults: .ephemeral())
        settings.timeFormat = .twentyFourHour
        let rules = AlertFixtures.rules(server, settings: settings)
        let rule = AlertRule(kind: .thisTrip, trip: AlertFixtures.trip(), route: route)

        let saving = Task { await rules.save(rule) }
        await server.waitUntilHolding()
        XCTAssertEqual(rules.state(of: rule), .settingUp)

        await server.release()
        await saving.value
        XCTAssertEqual(rules.state(of: rule), .on)
        let registrations = await server.registrations
        XCTAssertEqual(registrations, [InstallationRegistration(deviceToken: String(repeating: "0", count: 64), timeFormat: "24h", environment: "sandbox")])
        let saved = await server.saved
        XCTAssertEqual(saved, [rule])
    }

    func testASaveInFlightSendsOneRequest() async {
        let server = FakeAlertServer()
        await server.holdSaves()
        let rules = AlertFixtures.rules(server)
        let rule = AlertRule(kind: .thisTrip, trip: AlertFixtures.trip(), route: route)

        let first = Task { await rules.save(rule) }
        await server.waitUntilHolding()
        await rules.save(rule)
        await rules.save(AlertRule(kind: .thisTrip, trip: AlertFixtures.trip(), route: route))
        await server.release()
        await first.value

        let saved = await server.saved
        XCTAssertEqual(saved.map(\.id), [rule.id])
        XCTAssertEqual(rules.rules.count, 1)
    }

    func testAnUnreachableServerKeepsTheRuleAsCouldNotSaveAndSavingAgainRetriesIt() async {
        let server = FakeAlertServer()
        await server.setFailing(true)
        let rules = AlertFixtures.rules(server)
        let rule = AlertRule(kind: .thisTrip, trip: AlertFixtures.trip(), route: route)

        await rules.save(rule)
        XCTAssertEqual(rules.state(of: rule), .couldNotSave)
        XCTAssertEqual(rules.rules, [rule])

        await server.setFailing(false)
        await rules.save(rule)
        XCTAssertEqual(rules.state(of: rule), .on)
        let saved = await server.saved
        XCTAssertEqual(saved.map(\.id), [rule.id])
    }

    func testNotificationsOffIsNeverOnButTheRuleIsStillSaved() async {
        let server = FakeAlertServer()
        let rules = AlertFixtures.rules(server, permission: .off)
        let rule = AlertRule(kind: .thisTrip, trip: AlertFixtures.trip(), route: route)

        await rules.save(rule)
        XCTAssertEqual(rules.state(of: rule), .notificationsOff)
        let saved = await server.saved
        XCTAssertEqual(saved.count, 1)
    }

    func testAnUnknownInstallationRegistersAgain() async {
        let server = FakeAlertServer()
        await server.answerUnknownInstallationOnce()
        let rules = AlertFixtures.rules(server)
        let rule = AlertRule(kind: .thisTrip, trip: AlertFixtures.trip(), route: route)

        await rules.save(rule)
        XCTAssertEqual(rules.state(of: rule), .on)
        let registrations = await server.registrations
        XCTAssertEqual(registrations.count, 2)
    }

    func testDeleteRemovesAtOnceAndRetriesTheServerLater() async {
        let server = FakeAlertServer()
        let rules = AlertFixtures.rules(server)
        let rule = AlertRule(kind: .thisTrip, trip: AlertFixtures.trip(), route: route)
        await rules.save(rule)

        await server.setFailing(true)
        await rules.delete(rule.id)
        XCTAssertEqual(rules.rules, [])

        await server.setFailing(false)
        await rules.save(AlertRule(kind: .thisTrip, trip: AlertFixtures.trip("LW-0758-20261105"), route: route))
        let deleted = await server.deleted
        XCTAssertEqual(deleted, [rule.id])
    }

    func testEnablingTheSameTrainAgainUpdatesTheExistingRule() async {
        let server = FakeAlertServer()
        let rules = AlertFixtures.rules(server)
        let thisTrip = AlertRule(kind: .thisTrip, trip: AlertFixtures.trip(), route: route)
        let usual = AlertRule(kind: .repeating, trip: AlertFixtures.trip(), route: route, weekdays: [1, 2, 3, 4, 5])
        await rules.save(thisTrip)
        await rules.save(usual)

        // The same train again, and the usual 7:32 AM train picked on another day.
        await rules.save(AlertRule(kind: .thisTrip, trip: AlertFixtures.trip(), route: route))
        await rules.save(AlertRule(kind: .repeating, trip: AlertFixtures.trip("LW-0732-20261106", day: 6), route: route, weekdays: [1, 2]))

        XCTAssertEqual(rules.rules.map(\.id).sorted(), [thisTrip.id, usual.id].sorted())
        XCTAssertEqual(rules.rules.first { $0.kind == .repeating }?.weekdays, [1, 2])
        XCTAssertNil(rules.matching(AlertRule(kind: .repeating, trip: AlertFixtures.trip("LW-0758-20261105", departure: "12:58"), route: route, weekdays: [1])))
    }

    func testATripIsWatchedWhileItsThisTripRuleIsOn() async {
        let server = FakeAlertServer()
        let rules = AlertFixtures.rules(server)
        let trip = AlertFixtures.trip()
        XCTAssertFalse(rules.isWatched(trip.key))

        await rules.save(AlertRule(kind: .repeating, trip: trip, route: route, weekdays: [1, 2, 3, 4, 5]))
        XCTAssertFalse(rules.isWatched(trip.key))

        let rule = AlertRule(kind: .thisTrip, trip: trip, route: route)
        await server.setFailing(true)
        await rules.save(rule)
        XCTAssertFalse(rules.isWatched(trip.key))

        await server.setFailing(false)
        await rules.save(rule)
        XCTAssertTrue(rules.isWatched(trip.key))
        XCTAssertFalse(rules.isWatched(AlertFixtures.trip("LW-0758-20261105").key))

        // Paused on the Alerts tab (TT-143): no notifications, so not watched.
        var paused = rule
        paused.paused = true
        await rules.save(paused)
        XCTAssertFalse(rules.isWatched(trip.key))
        await rules.save(rule)
        XCTAssertTrue(rules.isWatched(trip.key))

        await rules.delete(rule.id)
        XCTAssertFalse(rules.isWatched(trip.key))
    }

    func testRulesAndTheInstallationStayOnDevice() async {
        let defaults = UserDefaults.ephemeral()
        let server = FakeAlertServer()
        let rules = AlertFixtures.rules(server, defaults: defaults)
        let rule = AlertRule(kind: .thisTrip, trip: AlertFixtures.trip(), route: route)
        await rules.save(rule)

        let relaunched = AlertFixtures.rules(server, defaults: defaults)
        XCTAssertEqual(relaunched.installation, rules.installation)
        XCTAssertEqual(relaunched.rules, [rule])
        XCTAssertEqual(relaunched.state(of: rule), .on)
        XCTAssertEqual(rule.trip, AlertFixtures.trip().key)
    }

    // MARK: Alerts tab (TT-143)

    func testRefreshReadsReviewNeededFromTheServerAndBackToOnOnceCleared() async {
        let server = FakeAlertServer()
        let rules = AlertFixtures.rules(server)
        let rule = AlertRule(kind: .repeating, trip: AlertFixtures.trip(), route: route, weekdays: [1, 2, 3, 4, 5])
        await rules.save(rule)

        await server.setStatuses([AlertRuleStatus(id: rule.id, state: .reviewNeeded, noMatchingTrainOn: "20261105")])
        await rules.refresh()
        XCTAssertEqual(rules.state(of: rule), .reviewNeeded)
        XCTAssertTrue(rules.needsReview)
        XCTAssertTrue(rules.hasNoMatchingTrain(rule, on: ServiceDay(year: 2026, month: 11, day: 5)))
        XCTAssertFalse(rules.hasNoMatchingTrain(rule, on: ServiceDay(year: 2026, month: 11, day: 6)))

        await server.setStatuses([AlertRuleStatus(id: rule.id, state: .on)])
        await rules.refresh()
        XCTAssertEqual(rules.state(of: rule), .on)
        XCTAssertFalse(rules.needsReview)
    }

    /// A pause that never reached the server: the server still lists the rule as On, but the row keeps Try again.
    func testRefreshKeepsARuleThatCouldNotBeSaved() async {
        let server = FakeAlertServer()
        let rules = AlertFixtures.rules(server)
        var rule = AlertRule(kind: .repeating, trip: AlertFixtures.trip(), route: route, weekdays: [1, 2, 3, 4, 5])
        await rules.save(rule)

        rule.paused = true
        await server.setFailing(true)
        await rules.save(rule)
        XCTAssertEqual(rules.state(of: rule), .couldNotSave)

        await server.setFailing(false)
        await server.setStatuses([AlertRuleStatus(id: rule.id, state: .on)])
        await rules.refresh()
        XCTAssertEqual(rules.state(of: rule), .couldNotSave)
    }

    func testRefreshWithTheServerUnreachableKeepsEveryState() async {
        let server = FakeAlertServer()
        let rules = AlertFixtures.rules(server)
        let rule = AlertRule(kind: .thisTrip, trip: AlertFixtures.trip(), route: route)
        await rules.save(rule)

        await server.setFailing(true)
        await rules.refresh()
        XCTAssertEqual(rules.state(of: rule), .on)
    }

    func testRestorePutsADeletedRuleBackAndSavesItAgainWithTheSameId() async {
        let server = FakeAlertServer()
        let rules = AlertFixtures.rules(server)
        let first = AlertRule(kind: .thisTrip, trip: AlertFixtures.trip(), route: route)
        let second = AlertRule(kind: .thisTrip, trip: AlertFixtures.trip("LW-0758-20261105", departure: "12:58"), route: route)
        await rules.save(first)
        await rules.save(second)

        await rules.delete(first.id)
        await rules.restore(first, at: 1)

        XCTAssertEqual(rules.rules.map(\.id), [second.id, first.id])
        XCTAssertEqual(rules.state(of: first), .on)
        let deleted = await server.deleted
        let saved = await server.saved
        XCTAssertEqual(deleted, [first.id])
        XCTAssertEqual(saved.map(\.id), [first.id, second.id, first.id])
    }
}
