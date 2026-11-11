import XCTest
@testable import TrainTimes

/// TT-118, TT-163: every fact shown comes from the feed or the schedule, and a missing estimate is left out, never guessed.
@MainActor
final class TripDetailsViewModelTests: XCTestCase {
    private let formatter = TimeFormatter(format: .twelveHour)

    func testOnTimeJourneyCard() async throws {
        let model = try await TripDetailsViewModel.loadedFixture()
        let details = try XCTUnwrap(model.details(formatter))
        XCTAssertEqual(details.title, "7:32 AM train")
        XCTAssertEqual(model.route.line?.name, "Lakeshore West")
        XCTAssertEqual(details.origin, "Oakville GO")
        XCTAssertEqual(details.destination, "Union Station GO")
        XCTAssertEqual(details.departure, TripDetails.Time(value: "7:32 AM"))
        XCTAssertEqual(details.arrival, TripDetails.Time(value: "8:12 AM"), "The feed gives no arrival estimate for this trip")
        XCTAssertEqual(details.countdown, "in 11 min")
        XCTAssertEqual(details.platform, "Platform 2")
        XCTAssertTrue(details.hasPlatform)
        XCTAssertFalse(details.isExpress)
        XCTAssertEqual(details.tripLength, "40 min")
        XCTAssertEqual(details.status, .onTime)
        XCTAssertEqual(details.freshnessText, "Updated just now")
        XCTAssertFalse(details.isCancelled)
        XCTAssertFalse(details.isTrainCancelled)
        XCTAssertEqual(details.stopCount, "7 stops")
        XCTAssertEqual(details.stopsHeader, "Scheduled")
        XCTAssertEqual(details.stops.map(\.time), ["7:32 AM", "7:40 AM", "7:46 AM", "7:52 AM", "7:57 AM", "8:04 AM", "8:12 AM"])
        XCTAssertEqual(details.stops.map(\.isEnd), [true, false, false, false, false, false, true])
        XCTAssertEqual(details.footnote, "Arrival times are scheduled.")
        XCTAssertEqual(details.alertButton, "Alert me")
        XCTAssertTrue(details.showsDirections)
    }

    /// TT-189, TT-192: the bar reads the train's one alert from the alert rules, live: a repeating alert covering this
    /// train's day says Alert on with its days at once, and switched off it says Alert me again.
    func testTheAlertBarReadsTheTrainsAlert() async throws {
        let rules = AlertFixtures.rules(FakeAlertServer())
        let model = try await alertModel(rules)
        XCTAssertEqual(model.details(formatter)?.alertButton, "Alert me")
        XCTAssertEqual(model.bell, .off)

        let trip = try XCTUnwrap(model.departure?.trip)
        var alert = AlertRule(kind: .repeating, trip: trip, route: model.route, weekdays: [1, 2, 3, 4, 5])
        await rules.save(alert)
        XCTAssertTrue(model.hasAlert)
        XCTAssertEqual(model.bell, .on)
        XCTAssertEqual(model.details(formatter)?.alertButton, "Alert on")
        XCTAssertEqual(model.repeatTitle, "Mon to Fri")

        alert.weekdays = [1, 3, 5, 6]
        await rules.save(alert)
        XCTAssertEqual(model.repeatTitle, "4 days", "Mon, Wed, Fri, Sat does not fit")

        alert.paused = true
        await rules.save(alert)
        XCTAssertFalse(model.hasAlert)
        XCTAssertEqual(model.details(formatter)?.alertButton, "Alert me")
        XCTAssertEqual(model.repeatTitle, "Repeat")
    }

    /// TT-192: "Alert me" turns the alert on in place, with no capsule in the sheet (the bar says it); "Alert on" turns it
    /// off, again with no capsule.
    func testAlertMeTurnsTheAlertOnInPlaceAndAlertOnTurnsItOff() async throws {
        let server = FakeAlertServer()
        let rules = AlertFixtures.rules(server)
        let model = try await alertModel(rules)

        await model.tapAlert()
        XCTAssertEqual(model.bell, .on)
        XCTAssertEqual(model.details(formatter)?.alertButton, "Alert on")
        XCTAssertEqual(rules.rules.map(\.kind), [.thisTrip])
        XCTAssertNil(model.capsule, "Alert on is the bar's own word")
        XCTAssertEqual(model.bells?.enabledCount, 1)

        await model.tapAlert()
        XCTAssertEqual(model.bell, .off)
        XCTAssertEqual(model.details(formatter)?.alertButton, "Alert me")
        XCTAssertTrue(rules.rules.isEmpty)
        XCTAssertNil(model.capsule)
    }

    /// TT-192: Repeat opens the day panel in the sheet with Mon to Fri on this weekday train, the same alert repeats, and
    /// Repeat then reads its days; tapped again it closes the panel.
    func testRepeatOpensTheDayPanelAndTheSameAlertRepeats() async throws {
        let rules = AlertFixtures.rules(FakeAlertServer())
        let model = try await alertModel(rules)
        await model.tapAlert()
        let id = try XCTUnwrap(rules.rules.first?.id)

        model.tapRepeat()
        XCTAssertEqual(model.capsule?.isPanelOpen, true)
        XCTAssertEqual(model.capsule?.panelDays, [1, 2, 3, 4, 5])
        XCTAssertEqual(model.repeatTitle, "Mon to Fri")
        await eventually { rules.rules.first?.kind == .repeating }
        XCTAssertEqual(rules.rules.map(\.id), [id], "the same alert")
        XCTAssertEqual(rules.rules.first?.weekdays, [1, 2, 3, 4, 5])

        model.bells?.toggleDay(6)
        await eventually { rules.rules.first?.weekdays == [1, 2, 3, 4, 5, 6] }

        model.tapRepeat()
        XCTAssertNil(model.capsule)
        XCTAssertEqual(model.repeatTitle, "Mon to Sat")
        XCTAssertEqual(model.bell, .on)

        // Opened again, the panel shows the alert's days and saves nothing.
        model.tapRepeat()
        XCTAssertEqual(model.capsule?.panelDays, [1, 2, 3, 4, 5, 6])
    }

    /// TT-192, D72: with notifications off a tap saves nothing, the bar's bell shakes and the capsule shows in the sheet.
    func testARefusalShowsTheCapsuleInTheSheet() async throws {
        let rules = AlertFixtures.rules(FakeAlertServer(), permission: .off)
        let model = try await alertModel(rules)

        await model.tapAlert()
        XCTAssertEqual(model.capsule?.kind, .notificationsOff)
        XCTAssertEqual(model.bellShakes, 1)
        XCTAssertEqual(model.bell, .off)
        XCTAssertTrue(rules.rules.isEmpty)
    }

    /// The 7:32 AM fixture train with the alert rules and the sheet's own bell model, loaded.
    private func alertModel(_ rules: AlertRules) async throws -> TripDetailsViewModel {
        let repository = try FixtureScheduleRepository(bundle: Bundle(for: Self.self))
        let model = TripDetailsViewModel(
            route: repository.route, key: TripKey(serviceDay: repository.serviceDay, tripId: TripDetailsViewModel.fixtureTripId),
            repository: repository, clock: FixedClock(now: repository.now), alerts: rules,
            bells: AlertBellModel(rules: rules, refusalDelay: .zero, afterPrompt: {})
        )
        await model.load()
        return model
    }

    /// Waits up to 3 s for work the bell model runs in its own task (the panel's saves).
    private func eventually(
        _ condition: () async -> Bool, file: StaticString = #filePath, line: UInt = #line
    ) async {
        for _ in 0..<300 {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out", file: file, line: line)
    }

    /// Delayed: both times are the expected ones in delay-ink, the scheduled ones struck under them.
    func testDelayedStrikesTheScheduledTimes() async throws {
        let model = try await TripDetailsViewModel.loadedFixture(.delayed, hasAlert: true)
        let details = try XCTUnwrap(model.details(formatter))
        XCTAssertEqual(details.status, .delayed(minutes: 9))
        XCTAssertEqual(details.departure, TripDetails.Time(value: "7:41 AM", scheduled: "7:32 AM", isLate: true))
        XCTAssertEqual(details.arrival, TripDetails.Time(value: "8:21 AM", scheduled: "8:12 AM", isLate: true))
        XCTAssertEqual(details.countdown, "in 20 min", "The countdown runs to the expected departure")
        XCTAssertEqual(details.tripLength, "40 min")
        XCTAssertEqual(details.freshnessText, "Updated just now")
        XCTAssertEqual(details.stopCount, "7 stops")
        XCTAssertEqual(details.stopsHeader, "Expected")
        XCTAssertEqual(details.stops.map(\.name), [
            "Oakville GO", "Clarkson GO", "Port Credit GO", "Long Branch GO", "Mimico GO", "Exhibition GO", "Union Station GO",
        ])
        XCTAssertEqual(details.stops.map(\.time), ["7:41 AM", "7:49 AM", "7:55 AM", "8:01 AM", "8:06 AM", "8:13 AM", "8:21 AM"])
        XCTAssertEqual(details.footnote, "Arrival times are estimates from the live feed. Scheduled arrival 8:12 AM.")
        XCTAssertEqual(details.alertButton, "Alert on")
    }

    /// Timetable only: ink times, the Scheduled ring and the service day, "Platform —", the Express bolt on express trains.
    func testTimetableOnly() async throws {
        let model = try await TripDetailsViewModel.timetableOnlyFixture()
        let details = try XCTUnwrap(model.details(formatter))
        XCTAssertEqual(details.status, .scheduled)
        XCTAssertEqual(details.departure, TripDetails.Time(value: "7:58 AM"))
        XCTAssertEqual(details.arrival, TripDetails.Time(value: "8:38 AM"))
        XCTAssertEqual(details.platform, "Platform —")
        XCTAssertFalse(details.hasPlatform)
        XCTAssertTrue(details.isExpress)
        XCTAssertEqual(details.freshnessText, "Thu, Nov 5", "The service day takes the place of \"Scheduled times only\"")
        XCTAssertEqual(details.stopsHeader, "Scheduled")
        XCTAssertEqual(details.alertButton, "Alert me")
    }

    /// Acceptance: a trip with no estimate shows only scheduled values.
    func testNoEstimateShowsOnlyScheduledValues() async throws {
        let model = try await TripDetailsViewModel.loadedFixture(tripId: "LW-0821-20261105")
        let details = try XCTUnwrap(model.details(formatter))
        XCTAssertEqual(details.status, .scheduled, "No live status: Scheduled, as on the card (D50)")
        XCTAssertEqual(details.departure, TripDetails.Time(value: "8:21 AM"))
        XCTAssertEqual(details.arrival, TripDetails.Time(value: "9:01 AM"))
        XCTAssertEqual(details.platform, "Platform —")
        XCTAssertTrue(details.isExpress)
        XCTAssertEqual(details.stopsHeader, "Scheduled")
        XCTAssertEqual(details.stops.first?.time, "8:21 AM")
        XCTAssertEqual(details.stops.last?.time, "9:01 AM")
    }

    /// Stale live data drops every estimate (D13): the status falls back to Scheduled (D50) and the stops show scheduled times.
    func testStaleDataShowsNoEstimates() async throws {
        let model = try await TripDetailsViewModel.loadedFixture(.delayed, minutesLater: 5)
        let details = try XCTUnwrap(model.details(formatter))
        XCTAssertEqual(details.status, .scheduled)
        XCTAssertEqual(details.departure, TripDetails.Time(value: "7:32 AM"))
        XCTAssertEqual(details.arrival, TripDetails.Time(value: "8:12 AM"))
        XCTAssertEqual(details.stopsHeader, "Scheduled")
        XCTAssertEqual(details.stops.first?.time, "7:32 AM")
        XCTAssertEqual(details.freshnessText, "Last reported 7:21 AM")
    }

    func testOfflineFreshnessSlot() async throws {
        let model = try await TripDetailsViewModel.loadedFixture(.offline)
        let details = try XCTUnwrap(model.details(formatter))
        XCTAssertEqual(details.status, .scheduled)
        XCTAssertEqual(details.freshnessText, "Offline · last updated 6:52 AM")
        XCTAssertEqual(details.platform, "Platform —", "A cached platform may have changed")
    }

    /// The countdown is the next usable train's alone, as on the cards: not a later train, not a cancelled one.
    func testCountdownOnlyOnTheNextUsableTrain() async throws {
        let next = try await TripDetailsViewModel.loadedFixture()
        XCTAssertEqual(next.details(formatter)?.countdown, "in 11 min")
        let later = try await TripDetailsViewModel.loadedFixture(tripId: "LW-0758-20261105")
        XCTAssertNil(later.details(formatter)?.countdown)

        // 7:32 is cancelled, so 7:58 is the next usable train.
        let cancelled = try await TripDetailsViewModel.loadedFixture(.cancelled)
        XCTAssertNil(cancelled.details(formatter)?.countdown)
        let nextAfterCancelled = try await TripDetailsViewModel.loadedFixture(.cancelled, tripId: "LW-0758-20261105")
        XCTAssertEqual(nextAfterCancelled.details(formatter)?.countdown, "in 37 min")
    }

    func testCancelledHidesTheButtonAndSaysSo() async throws {
        let model = try await TripDetailsViewModel.loadedFixture(.cancelled, hasAlert: true)
        let details = try XCTUnwrap(model.details(formatter))
        XCTAssertTrue(details.isCancelled)
        XCTAssertTrue(details.isTrainCancelled, "Every stop time is struck only for a cancelled train")
        XCTAssertEqual(details.status, .cancelled)
        XCTAssertEqual(details.departure, TripDetails.Time(value: "7:32 AM"))
        XCTAssertEqual(details.arrival, TripDetails.Time(value: "8:12 AM"))
        XCTAssertNil(details.alertButton, "No alert for a cancelled train, even one that has an alert")
        XCTAssertFalse(model.showsAlertButton)
        XCTAssertEqual(details.footnote, "This train is cancelled. Times are the timetable's.")
        XCTAssertEqual(details.stopsHeader, "Scheduled")
        XCTAssertEqual(details.freshnessText, "Updated just now")
    }

    func testDepartedShowsTheActualTimeAndHidesAlert() async throws {
        let model = try await TripDetailsViewModel.departedFixture()
        let details = try XCTUnwrap(model.details(formatter))
        XCTAssertTrue(model.hasDeparted)
        XCTAssertEqual(details.status, .departed)
        XCTAssertEqual(details.status.text, "Departed")
        XCTAssertEqual(details.departure, TripDetails.Time(value: "7:43 AM", scheduled: "7:32 AM", isLate: true))
        XCTAssertEqual(details.arrival, TripDetails.Time(value: "8:23 AM", scheduled: "8:12 AM", isLate: true))
        XCTAssertEqual(details.stops.last?.time, "8:23 AM")
        XCTAssertNil(details.countdown)
        XCTAssertNil(details.alertButton)
    }

    func testScheduledTrainThatHasLeftOffersNoAlert() async throws {
        let model = try await TripDetailsViewModel.loadedFixture(tripId: "LW-0821-20261105", minutesLater: 61)
        let details = try XCTUnwrap(model.details(formatter))
        XCTAssertEqual(details.status, .scheduled, "Without live data the sheet never claims the train departed")
        XCTAssertNil(details.departure.scheduled)
        XCTAssertNil(details.alertButton)
    }

    func testSkippedStopKeepsItsScheduledTimeStruck() async throws {
        let model = try await TripDetailsViewModel.departedFixture(skipping: ["MO"])
        let details = try XCTUnwrap(model.details(formatter))
        let mimico = try XCTUnwrap(details.stops.first { $0.id == "MO" })
        XCTAssertTrue(mimico.isSkipped)
        XCTAssertEqual(mimico.time, "7:57 AM")
        XCTAssertEqual(details.stopsHeader, "Expected")
    }

    func testLongTripCountsEveryStop() async throws {
        let model = try await TripDetailsViewModel.longTripFixture()
        let details = try XCTUnwrap(model.details(formatter))
        XCTAssertEqual(details.stopCount, "12 stops")
        XCTAssertEqual(details.origin, "West Harbour GO")
        XCTAssertEqual(details.destination, "Union Station GO")
        XCTAssertEqual(details.tripLength, "64 min")
        XCTAssertEqual(details.stops.map(\.isEnd).filter { $0 }.count, 2)
        XCTAssertEqual(details.alertButton, "Alert me")
    }

    // MARK: Directions (TT-188, D64)

    /// The link opens Apple Maps with directions to the departure station, at its place from the feed.
    func testDirectionsOpenMapsAtTheDepartureStation() async throws {
        let maps = FakeMapsOpener()
        let model = try await directionsFixture(.delayed, maps: maps)
        XCTAssertEqual(model.details(formatter)?.showsDirections, true, "A delayed train that has not left yet")
        model.openDirections()
        XCTAssertEqual(maps.opened, [.init(name: "Oakville GO", place: GeoPoint(latitude: 43.455594, longitude: -79.682242))])
    }

    func testNoDirectionsOnACancelledTrain() async throws {
        let maps = FakeMapsOpener()
        let model = try await directionsFixture(.cancelled, maps: maps)
        XCTAssertEqual(model.details(formatter)?.showsDirections, false)
        model.openDirections()
        XCTAssertTrue(maps.opened.isEmpty)
    }

    func testNoDirectionsOnceTheTrainHasLeft() async throws {
        let departed = try await TripDetailsViewModel.departedFixture()
        XCTAssertEqual(departed.details(formatter)?.showsDirections, false, "Left at 7:43 AM by the live feed")
        let scheduled = try await TripDetailsViewModel.loadedFixture(tripId: "LW-0821-20261105", minutesLater: 61)
        XCTAssertEqual(scheduled.details(formatter)?.showsDirections, false, "No live data: its scheduled 8:21 AM has passed")
    }

    func testNoDirectionsWithoutTheStationsPlace() async throws {
        let model = try await TripDetailsViewModel.longTripFixture()
        XCTAssertEqual(model.details(formatter)?.showsDirections, false, "The stops of this fixture have no coordinates")
    }

    /// One fixture trip (the 7:32 AM train) at 7:21 AM, with the Maps opener a test hands it.
    private func directionsFixture(
        _ scenario: FixtureScheduleRepository.Scenario, maps: FakeMapsOpener
    ) async throws -> TripDetailsViewModel {
        let repository = try FixtureScheduleRepository(scenario: scenario, bundle: Bundle(for: Self.self))
        let model = TripDetailsViewModel(
            route: repository.route,
            key: TripKey(serviceDay: repository.serviceDay, tripId: TripDetailsViewModel.fixtureTripId),
            repository: repository,
            clock: FixedClock(now: repository.now),
            maps: maps
        )
        await model.load()
        return model
    }

    func testUnknownTripShowsNothing() async throws {
        let model = try await TripDetailsViewModel.loadedFixture(tripId: "LW-0000")
        XCTAssertNil(model.details(formatter))
    }
}
