import XCTest
@testable import TrainTimes

/// The Alerts tab (TT-143): rows in state order with their words, the switch, swipe to delete with undo on the server,
/// Alert setup for rows that need action, recent updates, line notices and the tab dot.
@MainActor
final class AlertsViewModelTests: XCTestCase {
    private let formatter = TimeFormatter(format: .twelveHour)

    func testRowsListReviewNeededAndCouldNotSaveFirstThenOnThenPaused() async {
        let server = FakeAlertServer()
        let rules = await AlertsFixtures.rules(
            server, on: [AlertsFixtures.evening, AlertsFixtures.morning], reviewNeeded: [AlertsFixtures.burlington],
            couldNotSave: [AlertsFixtures.today]
        )
        let model = await AlertsFixtures.model(rules)

        let rows = model.ruleRows(formatter)
        XCTAssertEqual(rows.map(\.id), ["today", "burlington", "morning", "evening"])
        XCTAssertEqual(rows.map(\.state), [.couldNotSave, .reviewNeeded, .on, .paused])
        XCTAssertEqual(rows.map(\.accessory), [
            .chevron, .chevron, .toggle(isOn: true, isEnabled: true), .toggle(isOn: false, isEnabled: true),
        ])
        XCTAssertFalse(model.isEmpty)
    }

    func testRowsNameTheTrainDirectionAndDays() async {
        let server = FakeAlertServer()
        let tomorrow = AlertRule(
            id: "tomorrow", kind: .thisTrip, trip: AlertFixtures.trip("LW-0732-20261106", day: 6), route: AlertsFixtures.oakvilleToUnion
        )
        let rules = await AlertsFixtures.rules(server, on: [tomorrow, AlertsFixtures.today, AlertsFixtures.morning])
        let model = await AlertsFixtures.model(rules)

        let rows = model.ruleRows(formatter)
        XCTAssertEqual(rows.map(\.title), ["7:32 AM · Oakville to Union", "8:21 AM · Oakville to Union", "7:32 AM · Oakville to Union"])
        XCTAssertEqual(rows.map(\.days), ["Mon to Fri", "Today only", "Fri, Nov 6"])
        XCTAssertEqual(rows.first?.testID, "alerts.rule.repeat.LW-0732-20261105")
    }

    func testARepeatRuleWithNoTrainTodaySaysSo() async {
        let server = FakeAlertServer()
        let rules = await AlertsFixtures.rules(server, on: [AlertsFixtures.morning])
        await server.setStatuses([AlertRuleStatus(id: "morning", state: .on, noMatchingTrainOn: "20261105")])
        await rules.refresh()
        let model = await AlertsFixtures.model(rules)

        XCTAssertEqual(model.ruleRows(formatter).first?.days, "Mon to Fri · No matching train today")
    }

    func testThisTripRulesForAPastDayAreNotListed() async {
        let server = FakeAlertServer()
        let yesterday = AlertRule(kind: .thisTrip, trip: AlertFixtures.trip("LW-0732-20261104", day: 4), route: AlertsFixtures.oakvilleToUnion)
        let rules = await AlertsFixtures.rules(server, on: [yesterday])
        let model = await AlertsFixtures.model(rules)

        XCTAssertTrue(model.ruleRows(formatter).isEmpty)
        XCTAssertTrue(model.isEmpty)
    }

    func testTheSwitchPausesAndResumesTheRuleOnTheServer() async {
        let server = FakeAlertServer()
        let rules = await AlertsFixtures.rules(server, on: [AlertsFixtures.morning])
        let model = await AlertsFixtures.model(rules)

        await model.setOn(false, for: "morning")?.value
        XCTAssertEqual(model.ruleRows(formatter).first?.state, .paused)
        var saved = await server.saved
        XCTAssertEqual(saved.last?.paused, true)

        await model.setOn(true, for: "morning")?.value
        XCTAssertEqual(model.ruleRows(formatter).first?.state, .on)
        saved = await server.saved
        XCTAssertEqual(saved.last?.paused, false)
        XCTAssertEqual(saved.last?.id, "morning")
    }

    func testTheSwitchWaitsWhileSettingUp() async {
        let server = FakeAlertServer()
        let rules = await AlertsFixtures.rules(server, on: [AlertsFixtures.morning])
        let model = await AlertsFixtures.model(rules)
        await server.holdSaves()

        let task = model.setOn(false, for: "morning")
        await server.waitUntilHolding()
        let row = model.ruleRows(formatter).first
        XCTAssertEqual(row?.state, .settingUp)
        XCTAssertEqual(row?.accessory, .toggle(isOn: false, isEnabled: false))

        await server.release()
        await task?.value
        XCTAssertEqual(model.ruleRows(formatter).first?.state, .paused)
    }

    func testDeleteHidesTheRowAtOnceAndUndoRestoresItOnTheServer() async {
        let server = FakeAlertServer()
        let rules = await AlertsFixtures.rules(server, on: [AlertsFixtures.evening, AlertsFixtures.morning])
        let model = await AlertsFixtures.model(rules)

        let deleting = model.delete("evening")
        XCTAssertEqual(model.ruleRows(formatter).map(\.id), ["morning"])
        XCTAssertEqual(model.deleted?.id, "evening")
        await deleting?.value
        let deleted = await server.deleted
        XCTAssertEqual(deleted, ["evening"])
        XCTAssertEqual(rules.rules.map(\.id), ["morning"])

        await model.undo()
        XCTAssertNil(model.deleted)
        XCTAssertEqual(rules.rules.map(\.id), ["morning", "evening"], "back where it was")
        XCTAssertEqual(model.ruleRows(formatter).map(\.state), [.on, .paused], "paused as before")
        let saved = await server.saved
        XCTAssertEqual(saved.last, AlertsFixtures.evening, "saved on the server again with the same id")
    }

    func testTheUndoToastGoesAfterItsTime() async throws {
        let server = FakeAlertServer()
        let rules = await AlertsFixtures.rules(server, on: [AlertsFixtures.morning])
        let model = await AlertsFixtures.model(rules, toastDuration: .milliseconds(100))

        let deleting = model.delete("morning")
        XCTAssertNotNil(model.deleted)
        await deleting?.value
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertNil(model.deleted)
        XCTAssertTrue(model.isEmpty)
    }

    func testARowThatNeedsActionOpensAlertSetupForItsRule() async {
        let server = FakeAlertServer()
        let rules = await AlertsFixtures.rules(server, reviewNeeded: [AlertsFixtures.burlington], couldNotSave: [AlertsFixtures.today])
        let model = await AlertsFixtures.model(rules)

        for id in ["burlington", "today"] {
            let request = try? XCTUnwrap(model.setupRequest(for: id))
            let sheet = request.map { AlertSetupViewModel(request: $0, rules: rules) }
            XCTAssertEqual(sheet?.rule?.id, id)
            XCTAssertEqual(sheet?.isManaging, true)
        }
        XCTAssertEqual(model.setupRequest(for: "burlington")?.kind, .repeating)
        XCTAssertEqual(model.setupRequest(for: "today")?.kind, .thisTrip)
    }

    func testRecentUpdatesAreTheLastSevenDaysNewestFirst() async {
        let old = AlertsFixtures.update(
            "old", title: "7:32 AM train cancelled", body: "", at: "2026-10-28T12:00:00Z", tripId: "LW-0732-20261028", serviceDate: "20261028"
        )
        let updates = await AlertsFixtures.updates([AlertsFixtures.updates[1], old, AlertsFixtures.updates[0]])
        let model = await AlertsFixtures.model(AlertFixtures.rules(FakeAlertServer()), updates: updates)

        let rows = model.updateRows(formatter)
        XCTAssertEqual(rows.map(\.id), ["delay", "recovery"])
        XCTAssertEqual(rows.map(\.time), ["Today, 7:29 AM", "Yesterday, 4:48 PM"])
        XCTAssertEqual(rows.map(\.kind), [.delay, .recovery])
        XCTAssertEqual(
            rows.first?.link,
            .trip(TripKey(serviceDay: ServiceDay(year: 2026, month: 11, day: 5), tripId: "LW-0732-20261105"), originId: "OA", destinationId: "UN")
        )
        XCTAssertNil(rows.last?.link, "yesterday's trip no longer opens")
    }

    func testOlderUpdatesShowTheirDate() {
        let date = try! Date("2026-11-02T21:48:00Z", strategy: .iso8601)
        XCTAssertEqual(AlertsViewModel.stamp(date, now: AlertsFixtures.now, formatter: formatter), "Mon, Nov 2, 4:48 PM")
    }

    func testLineNoticesNameTheLineWithTheirReportedTime() async {
        let model = await AlertsFixtures.model(AlertFixtures.rules(FakeAlertServer()), notices: [AlertsFixtures.notice])

        let rows = model.noticeRows(formatter)
        XCTAssertEqual(rows.map(\.line), ["Lakeshore West"])
        XCTAssertEqual(rows.map(\.summary), ["Delays of up to 15 min near Port Credit, as reported at 7:12 AM."])
        XCTAssertEqual(rows.map(\.time), ["Today, 7:12 AM"])
    }

    func testTheTabDotShowsForARuleToReviewUntilTheTabIsOpened() async {
        let server = FakeAlertServer()
        let rules = await AlertsFixtures.rules(server, on: [AlertsFixtures.morning])
        let model = await AlertsFixtures.model(rules)
        XCTAssertFalse(model.showsTabDot)

        await server.setStatuses([AlertRuleStatus(id: "morning", state: .reviewNeeded)])
        await model.refresh()
        XCTAssertTrue(rules.needsReview)
        XCTAssertTrue(model.showsTabDot)

        model.markReviewsSeen()
        XCTAssertFalse(model.showsTabDot)
    }
}
