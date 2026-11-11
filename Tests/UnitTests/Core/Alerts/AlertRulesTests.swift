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

    /// TT-169: the number the notifications-off warning speaks of leaves out paused rules and This-trip rules for a past day.
    func testSwitchedOnCountSkipsPausedRulesAndPastTrips() async {
        let rules = AlertFixtures.rules(FakeAlertServer())
        let today = AlertRule(kind: .thisTrip, trip: AlertFixtures.trip(day: 5), route: route)
        let yesterday = AlertRule(kind: .thisTrip, trip: AlertFixtures.trip("LW-0732-20261104", day: 4), route: route)
        let repeating = AlertRule(kind: .repeating, trip: AlertFixtures.trip("LW-0805-20261104", day: 4), route: route, weekdays: [1])
        let paused = AlertRule(kind: .repeating, trip: AlertFixtures.trip("LW-1710-20261105", departure: "22:10"), route: route, weekdays: [2], paused: true)
        for rule in [today, yesterday, repeating, paused] { await rules.save(rule) }

        XCTAssertEqual(rules.switchedOnCount(on: ServiceDay(year: 2026, month: 11, day: 5)), 2)
        XCTAssertEqual(rules.switchedOnCount(on: ServiceDay(year: 2026, month: 11, day: 6)), 1, "only the Repeat rule is left")
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

    /// TT-153: deleting the only alert with no connection: the next foreground sends the delete, so it stops notifying.
    func testRefreshSendsAMissedDeleteWhenNoRuleIsLeft() async {
        let server = FakeAlertServer()
        let rules = AlertFixtures.rules(server)
        let rule = AlertRule(kind: .thisTrip, trip: AlertFixtures.trip(), route: route)
        await rules.save(rule)

        await server.setFailing(true)
        await rules.delete(rule.id)
        await server.setFailing(false)
        await rules.refresh()
        let deleted = await server.deleted
        XCTAssertEqual(deleted, [rule.id])
    }

    /// TT-153: the server dropped the installation (APNs said the token is gone): the app registers again and saves the
    /// rule again rather than showing On while nothing watches it.
    func testRefreshAfterTheServerDroppedTheInstallationRegistersAndSavesAgain() async {
        let server = FakeAlertServer()
        let rules = AlertFixtures.rules(server)
        let rule = AlertRule(kind: .thisTrip, trip: AlertFixtures.trip(), route: route)
        await rules.save(rule)

        await server.answerUnknownInstallationOnce()
        await rules.refresh()
        XCTAssertEqual(rules.state(of: rule), .on)
        let registrations = await server.registrations
        XCTAssertEqual(registrations.count, 2)
        let saved = await server.saved
        XCTAssertEqual(saved.map(\.id), [rule.id, rule.id])
    }

    /// TT-153: a Time format change reaches the server on the next foreground, so notifications show times as the app does.
    func testRefreshSendsANewTimeFormat() async {
        let server = FakeAlertServer()
        let settings = AppSettings(defaults: .ephemeral())
        settings.timeFormat = .twelveHour
        let rules = AlertFixtures.rules(server, settings: settings)
        await rules.save(AlertRule(kind: .thisTrip, trip: AlertFixtures.trip(), route: route))

        settings.timeFormat = .twentyFourHour
        await rules.refresh()
        let registrations = await server.registrations
        XCTAssertEqual(registrations.map(\.timeFormat), ["12h", "24h"])
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
        let thisTrip = AlertRule(kind: .thisTrip, trip: AlertFixtures.trip("LW-0758-20261105", departure: "12:58"), route: route)
        let usual = AlertRule(kind: .repeating, trip: AlertFixtures.trip(), route: route, weekdays: [1, 2, 3, 4, 5])
        await rules.save(thisTrip)
        await rules.save(usual)

        // The same train again, and the usual 7:32 AM train picked on another day.
        await rules.save(AlertRule(kind: .thisTrip, trip: AlertFixtures.trip("LW-0758-20261105", departure: "12:58"), route: route))
        await rules.save(AlertRule(kind: .repeating, trip: AlertFixtures.trip("LW-0732-20261106", day: 6), route: route, weekdays: [1, 2]))

        XCTAssertEqual(rules.rules.map(\.id).sorted(), [thisTrip.id, usual.id].sorted())
        XCTAssertEqual(rules.rules.first { $0.kind == .repeating }?.weekdays, [1, 2])
        XCTAssertNil(rules.matching(AlertRule(kind: .repeating, trip: AlertFixtures.trip("LW-0805-20261105", departure: "13:05"), route: route, weekdays: [1])))
    }

    func testATrainIsWatchedWhileItsAlertIsOn() async {
        let server = FakeAlertServer()
        let rules = AlertFixtures.rules(server)
        let trip = AlertFixtures.trip()
        XCTAssertFalse(rules.isWatched(trip, on: route))

        let rule = AlertRule(kind: .thisTrip, trip: trip, route: route)
        await server.setFailing(true)
        await rules.save(rule)
        XCTAssertFalse(rules.isWatched(trip, on: route))
        XCTAssertTrue(rules.isAlerted(trip, on: route), "Trip details still says Manage alert")

        await server.setFailing(false)
        await rules.save(rule)
        XCTAssertTrue(rules.isWatched(trip, on: route))
        XCTAssertFalse(rules.isWatched(AlertFixtures.trip("LW-0758-20261105", departure: "12:58"), on: route))
        XCTAssertFalse(rules.isWatched(trip, on: AlertFixtures.route(("UN", "Union"), ("OA", "Oakville"))))

        // Paused on the Alerts tab (TT-143): no notifications, so not watched.
        var paused = rule
        paused.paused = true
        await rules.save(paused)
        XCTAssertFalse(rules.isWatched(trip, on: route))
        XCTAssertFalse(rules.isAlerted(trip, on: route))
        await rules.save(rule)
        XCTAssertTrue(rules.isWatched(trip, on: route))

        await rules.delete(rule.id)
        XCTAssertFalse(rules.isWatched(trip, on: route))
    }

    // MARK: One alert per card (TT-189)

    func testTheLookupFindsTheAlertThatCoversTheTrainOnItsDay() async throws {
        let rules = AlertFixtures.rules(FakeAlertServer())
        // 7:32 AM, Monday to Friday, set up on Thursday Nov 5; and the 7:58 AM train on Thursday only.
        await rules.save(AlertRule(kind: .repeating, trip: AlertFixtures.trip(), route: route, weekdays: [1, 2, 3, 4, 5]))
        await rules.save(AlertRule(kind: .thisTrip, trip: AlertFixtures.trip("LW-0758-20261105", departure: "12:58"), route: route))
        let repeating = try XCTUnwrap(rules.rules.first { $0.kind == .repeating })
        let oneDay = try XCTUnwrap(rules.rules.first { $0.kind == .thisTrip })

        XCTAssertEqual(rules.alert(for: AlertFixtures.trip("LW-0732-20261106", day: 6), on: route), repeating, "Friday")
        XCTAssertNil(rules.alert(for: AlertFixtures.trip("LW-0732-20261107", day: 7), on: route), "Saturday")
        XCTAssertEqual(rules.alert(for: AlertFixtures.trip("LW-0732-20261109", day: 9), on: route), repeating, "Monday")
        XCTAssertNil(rules.alert(for: AlertFixtures.trip(), on: AlertFixtures.route(("UN", "Union"), ("OA", "Oakville"))), "other way")
        XCTAssertEqual(rules.alert(for: AlertFixtures.trip("LW-0758-20261105", departure: "12:58"), on: route), oneDay)
        XCTAssertNil(rules.alert(for: AlertFixtures.trip("LW-0758-20261106", day: 6, departure: "12:58"), on: route), "one day only")

        // The watched-trip strip and Trip details read the same lookup: a repeating alert counts on each of its days.
        XCTAssertTrue(rules.isWatched(AlertFixtures.trip("LW-0732-20261106", day: 6), on: route))
        XCTAssertTrue(rules.isAlerted(AlertFixtures.trip("LW-0732-20261109", day: 9), on: route))
        XCTAssertFalse(rules.isAlerted(AlertFixtures.trip("LW-0732-20261107", day: 7), on: route))
    }

    func testAnAlertCountsAsAlertedWithNotificationsOffButIsNotWatched() async {
        let rules = AlertFixtures.rules(FakeAlertServer(), permission: .off)
        let trip = AlertFixtures.trip()
        await rules.save(AlertRule(kind: .repeating, trip: trip, route: route, weekdays: [4]))

        XCTAssertTrue(rules.isAlerted(trip, on: route))
        XCTAssertFalse(rules.isWatched(trip, on: route))
    }

    func testRepeatOnATrainWithAOneDayAlertChangesThatAlertUnderItsId() async throws {
        let server = FakeAlertServer()
        let rules = AlertFixtures.rules(server)
        let oneDay = AlertRule(kind: .thisTrip, trip: AlertFixtures.trip(), route: route)
        await rules.save(oneDay)

        await rules.save(AlertRule(kind: .repeating, trip: AlertFixtures.trip(), route: route, weekdays: [1, 2, 3, 4, 5]))

        let alert = try XCTUnwrap(rules.rules.first)
        XCTAssertEqual(rules.rules.count, 1)
        XCTAssertEqual(alert.id, oneDay.id)
        XCTAssertEqual(alert.kind, .repeating)
        XCTAssertEqual(alert.weekdays, [1, 2, 3, 4, 5])
        XCTAssertEqual(rules.state(of: alert), .on)
        let saved = await server.saved
        XCTAssertEqual(saved.map(\.id), [oneDay.id, oneDay.id], "a PUT on the same id")
        let deleted = await server.deleted
        XCTAssertEqual(deleted, [])
    }

    func testASavedRepeatMergesTheOneDayAlertsItCovers() async throws {
        let server = FakeAlertServer()
        let rules = AlertFixtures.rules(server)
        let wednesday = AlertRule(kind: .thisTrip, trip: AlertFixtures.trip("LW-0732-20261104", day: 4), route: route)
        let saturday = AlertRule(kind: .thisTrip, trip: AlertFixtures.trip("LW-0732-20261107", day: 7), route: route)
        await rules.save(wednesday)
        await rules.save(saturday)

        // Monday to Friday, set up from Friday's train: Wednesday's alert is now the same card's second alert.
        await rules.save(AlertRule(kind: .repeating, trip: AlertFixtures.trip("LW-0732-20261106", day: 6), route: route, weekdays: [1, 2, 3, 4, 5]))

        XCTAssertEqual(rules.rules.map(\.kind), [.repeating, .thisTrip])
        XCTAssertEqual(rules.rules.last?.id, saturday.id, "Saturday is not covered")
        let deleted = await server.deleted
        XCTAssertEqual(deleted, [wednesday.id])
    }

    func testARepeatThatIsOffOrNotSavedMergesNothingAndTheWorkingAlertWins() async throws {
        let server = FakeAlertServer()
        let rules = AlertFixtures.rules(server)
        let thursday = AlertRule(kind: .thisTrip, trip: AlertFixtures.trip("LW-0732-20261105"), route: route)
        let wednesday = AlertRule(kind: .thisTrip, trip: AlertFixtures.trip("LW-0732-20261104", day: 4), route: route)
        await rules.save(thursday)
        await rules.save(wednesday)

        // Switched off: Thursday's own alert is the one that works.
        let off = AlertRule(kind: .repeating, trip: AlertFixtures.trip("LW-0732-20261106", day: 6), route: route, weekdays: [1, 2, 3, 4, 5], paused: true)
        await rules.save(off)
        XCTAssertEqual(rules.rules.count, 3)
        XCTAssertEqual(rules.alert(for: AlertFixtures.trip(), on: route)?.id, thursday.id)

        // Switched on but the server cannot be reached: nothing is merged until it is saved.
        var on = try XCTUnwrap(rules.rules.first { $0.kind == .repeating })
        on.paused = false
        await server.setFailing(true)
        await rules.save(on)
        XCTAssertEqual(rules.rules.count, 3)
        XCTAssertEqual(rules.alert(for: AlertFixtures.trip(), on: route)?.id, thursday.id)

        await server.setFailing(false)
        await rules.save(on)
        XCTAssertEqual(rules.rules.map(\.id), [on.id])
        let deleted = await server.deleted
        XCTAssertEqual(Set(deleted), [thursday.id, wednesday.id])
    }

    func testOldDoublesAreMergedAtLaunchAndDeletedWithTheNextCall() async throws {
        struct Stored: Encodable {
            let rule: AlertRule
            let state: AlertRuleState
        }
        let defaults = UserDefaults.ephemeral()
        let server = FakeAlertServer()
        // An older build kept the 7:32 AM alert twice: Thursday only, and Monday to Friday.
        let oneDay = AlertRule(kind: .thisTrip, trip: AlertFixtures.trip(), route: route)
        let repeating = AlertRule(kind: .repeating, trip: AlertFixtures.trip(), route: route, weekdays: [1, 2, 3, 4, 5])
        let other = AlertRule(kind: .thisTrip, trip: AlertFixtures.trip("LW-0758-20261105", departure: "12:58"), route: route)
        let stored = [oneDay, repeating, other].map { Stored(rule: $0, state: .on) }
        defaults.set(try JSONEncoder().encode(stored), forKey: AlertRules.rulesKey)

        let rules = AlertFixtures.rules(server, defaults: defaults)
        XCTAssertEqual(rules.rules.map(\.id), [repeating.id, other.id])
        XCTAssertEqual(rules.alert(for: AlertFixtures.trip(), on: route)?.id, repeating.id)

        await rules.refresh()
        let deleted = await server.deleted
        XCTAssertEqual(deleted, [oneDay.id])
        XCTAssertEqual(AlertFixtures.rules(server, defaults: defaults).rules.map(\.id), [repeating.id, other.id], "kept merged")
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

    // MARK: Commit (TT-191, D71)

    /// A new alert the server cannot take is gone on device, its delete queued in case it got there.
    func testCommitOfANewAlertThatFailsLeavesNothingAndQueuesItsDelete() async {
        let server = FakeAlertServer()
        await server.setFailing(true)
        let defaults = UserDefaults.ephemeral()
        let rules = AlertFixtures.rules(server, defaults: defaults)
        let rule = AlertRule(kind: .thisTrip, trip: AlertFixtures.trip(), route: route)

        let kept = await rules.commit(rule)
        XCTAssertFalse(kept)
        XCTAssertEqual(rules.rules, [])
        XCTAssertEqual(defaults.stringArray(forKey: AlertRules.pendingDeletesKey), [rule.id])
    }

    /// A change the server cannot take goes back to the last saved version and its state.
    func testCommitOfAChangeThatFailsGoesBackToWhatWasSaved() async {
        let server = FakeAlertServer()
        let rules = AlertFixtures.rules(server)
        let rule = AlertRule(kind: .repeating, trip: AlertFixtures.trip(), route: route, weekdays: [1, 2, 3, 4, 5])
        await rules.save(rule)

        await server.setFailing(true)
        var changed = rule
        changed.weekdays = [1, 2, 3, 4, 5, 6]
        let kept = await rules.commit(changed)
        XCTAssertFalse(kept)
        XCTAssertEqual(rules.rules, [rule])
        XCTAssertEqual(rules.state(of: rule), .on)

        await server.setFailing(false)
        let keptNow = await rules.commit(changed)
        XCTAssertTrue(keptNow)
        XCTAssertEqual(rules.rules, [changed])
        XCTAssertEqual(rules.state(of: changed), .on)
    }

    /// An alert deleted while the server was unreachable and saved again (Undo) takes back its pending delete.
    func testCommitOfADeletedAlertTakesBackItsPendingDelete() async {
        let server = FakeAlertServer()
        let defaults = UserDefaults.ephemeral()
        let rules = AlertFixtures.rules(server, defaults: defaults)
        let rule = AlertRule(kind: .thisTrip, trip: AlertFixtures.trip(), route: route)
        await rules.save(rule)
        await server.setFailing(true)
        await rules.delete(rule.id)
        XCTAssertEqual(defaults.stringArray(forKey: AlertRules.pendingDeletesKey), [rule.id])

        await server.setFailing(false)
        let kept = await rules.commit(rule)
        XCTAssertTrue(kept)
        XCTAssertEqual(rules.rules, [rule])
        XCTAssertEqual(defaults.stringArray(forKey: AlertRules.pendingDeletesKey), [])
    }

    /// The bell's delete is gone on device before it returns; the server's part runs on.
    func testDeleteInBackgroundRemovesTheAlertOnDeviceAtOnce() async {
        let server = FakeAlertServer()
        let rules = AlertFixtures.rules(server)
        let rule = AlertRule(kind: .thisTrip, trip: AlertFixtures.trip(), route: route)
        await rules.save(rule)

        let delete = rules.deleteInBackground(rule.id)
        XCTAssertEqual(rules.rules, [])
        await delete.value
        let deleted = await server.deleted
        XCTAssertEqual(deleted, [rule.id])
    }
}
