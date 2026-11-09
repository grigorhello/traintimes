import XCTest
@testable import TrainTimes

/// TT-111: the timeline layout engine (requirements § Schedule screen, Timeline geometry).
final class TimelineLayoutTests: XCTestCase {
    private let day = ServiceDay(year: 2026, month: 11, day: 5)
    private let standard = TimelineCardSize.standard

    private func at(_ hour: Int, _ minute: Int) -> Date { day.date(hour: hour, minute: minute) }

    private func train(
        _ id: String, _ hour: Int, _ minute: Int, status: TrainStatus = .scheduled, expected: Date? = nil
    ) -> Departure {
        let scheduled = at(hour, minute)
        let trip = Trip(
            key: TripKey(serviceDay: day, tripId: id),
            scheduledDeparture: scheduled,
            scheduledArrival: scheduled.addingTimeInterval(40 * 60),
            platform: .pending,
            tags: []
        )
        return Departure(trip: trip, status: status, expectedDeparture: expected, expectedArrival: nil)
    }

    private func delayed7_32() -> Departure {
        train("LW-0732", 7, 32, status: .delayed(minutes: 9, reportedAt: at(7, 14)), expected: at(7, 41))
    }

    private func layout(
        _ departures: [Departure], now: Date? = nil, scale: CGFloat = TTTimeline.pointsPerMinute,
        sizes: [TripKey: TimelineCardSize] = [:]
    ) -> TimelineLayout {
        TimelineLayout(TimelineInput(departures: departures, now: now, pointsPerMinute: scale, cardSizes: sizes))
    }

    private func gridline(_ layout: TimelineLayout, _ hour: Int, _ minute: Int) throws -> TimelineLayout.Gridline {
        try XCTUnwrap(layout.gridlines.first { $0.time == at(hour, minute) }, "No gridline at \(hour):\(minute)")
    }

    // MARK: Minimum gap

    func testTwoTrainsOneMinuteApartZoomOnlyThatSegment() {
        let lead = train("a", 7, 52)
        let sizes = [lead.id: TimelineCardSize(height: 122, anchor: 35)]
        let result = layout([lead, train("b", 7, 53), train("c", 8, 13)], sizes: sizes)
        let cards = result.cards
        XCTAssertEqual(cards[0].bottom - cards[0].top, 122, accuracy: 0.001)
        XCTAssertEqual(cards[1].top - cards[0].bottom, TTTimeline.minCardGap, accuracy: 0.001, "Cards 16 pt apart")
        XCTAssertEqual(cards[2].markerY - cards[1].markerY, 20 * 7, accuracy: 0.001, "The next segment keeps its scale")
    }

    func testGridlinesFollowTheZoom() throws {
        let result = layout([train("a", 7, 44), train("b", 7, 46), train("c", 8, 10)])
        let (a, b) = (result.cards[0], result.cards[1])
        XCTAssertEqual(b.top - a.bottom, TTTimeline.minCardGap, accuracy: 0.001)
        XCTAssertEqual(try gridline(result, 7, 45).y, (a.markerY + b.markerY) / 2, accuracy: 0.001)
        XCTAssertEqual(try gridline(result, 8, 0).y, b.markerY + 14 * 7, accuracy: 0.001)
    }

    func testTrainsAtTheSameMinuteStillGetTheGap() {
        let cards = layout([train("a", 7, 32), train("b", 7, 32)]).cards
        XCTAssertEqual(cards[1].top - cards[0].bottom, TTTimeline.minCardGap, accuracy: 0.001)
    }

    // MARK: Fold

    func testFortyEightMinuteGapFolds() async throws {
        let repo = try FixtureScheduleRepository(scenario: .eveningDark, bundle: Bundle(for: TimelineLayoutTests.self))
        let trips = try await repo.trips(for: repo.route, on: repo.serviceDay)
        let live = try await repo.liveStatus(for: repo.route, on: repo.serviceDay)
        let departures = Departure.resolve(trips, live: live, freshness: Freshness(live, now: repo.now), isToday: true)
        // Short cards, so no card stretches the rail before the pill (testFoldPillClearsATallCardAbove covers that).
        let short = TimelineCardSize(height: 98, anchor: 33)
        let result = layout(departures, now: repo.now, sizes: Dictionary(uniqueKeysWithValues: departures.map { ($0.id, short) }))

        XCTAssertEqual(result.folds.count, 1)
        let fold = try XCTUnwrap(result.folds.first)
        XCTAssertEqual(fold.minutes, 48)
        XCTAssertEqual(fold.next, at(18, 40))
        XCTAssertEqual(fold.label(TimeFormatter(format: .twelveHour)), "No trains for 48 min · next 6:40 PM")

        // 30 min of rail: 10 min to scale beside each train, the dashed middle carries the pill.
        let (before, after) = (result.cards[2], result.cards[3])
        XCTAssertEqual(after.markerY - before.markerY, 30 * 7, accuracy: 0.001)
        XCTAssertEqual(fold.dashed.lowerBound, before.markerY + 70, accuracy: 0.001)
        XCTAssertEqual(fold.dashed.upperBound, after.markerY - 70, accuracy: 0.001)
        XCTAssertEqual(fold.pillY, before.markerY + 105, accuracy: 0.001)
        XCTAssertEqual(try gridline(result, 18, 0).y, before.markerY + 8 * 7, accuracy: 0.001)
        XCTAssertNil(result.gridlines.first { $0.time == at(18, 15) }, "No gridline inside the dashed part")
    }

    func testFoldLabelSkipsACancelledTrain() throws {
        let cancelled = train("b", 18, 0, status: .cancelled(reportedAt: at(16, 40)))
        let result = layout([train("a", 17, 0), cancelled, train("c", 18, 10)])
        let fold = try XCTUnwrap(result.folds.first)
        XCTAssertEqual(fold.next, at(18, 10))
        XCTAssertEqual(fold.minutes, 70, "Counted from the 5:00 PM train to the 6:10 PM one it names")
    }

    /// TT-153: a cancelled train at the start of a fold is left out too, so the label gives the real wait.
    func testFoldLabelCountsFromTheLastUsableTrain() throws {
        let cancelled = train("b", 17, 10, status: .cancelled(reportedAt: at(16, 40)))
        let result = layout([train("a", 17, 0), cancelled, train("c", 17, 50)])
        let fold = try XCTUnwrap(result.folds.first)
        XCTAssertEqual(fold.next, at(17, 50))
        XCTAssertEqual(fold.minutes, 50, "Counted from the 5:00 PM train, not the cancelled 5:10 PM one")
    }

    /// TT-153: when every train after a fold is cancelled, the fold names no next train and has no pill.
    func testFoldBeforeOnlyCancelledTrainsHasNoLabel() throws {
        let cancelled = train("b", 19, 0, status: .cancelled(reportedAt: at(17, 40)))
        let result = layout([train("a", 18, 0), cancelled])
        let fold = try XCTUnwrap(result.folds.first)
        XCTAssertNil(fold.next)
        XCTAssertNil(fold.label(TimeFormatter(format: .twelveHour)))
    }

    /// TT-153: a tall card before a fold (an Express row that wraps) stretches the rail so the pill stays readable.
    func testFoldPillClearsATallCardAbove() throws {
        let first = train("a", 17, 0)
        let result = layout([first, train("b", 17, 48)], sizes: [first.id: TimelineCardSize(height: 143, anchor: 35)])
        let fold = try XCTUnwrap(result.folds.first)
        XCTAssertGreaterThanOrEqual(fold.pillY - 11, result.cards[0].bottom + TTTimeline.minCardGap - 0.001)
        XCTAssertEqual(fold.minutes, 48)
    }

    func testLongWaitBeforeTheFirstTrainFolds() throws {
        let result = layout([train("a", 15, 50), train("b", 16, 20)], now: at(10, 0))
        let fold = try XCTUnwrap(result.folds.first)
        XCTAssertEqual(result.folds.count, 1)
        XCTAssertEqual(fold.minutes, 350)
        XCTAssertEqual(fold.next, at(15, 50))
        let nowY = try XCTUnwrap(result.nowY)
        XCTAssertEqual(nowY - result.initialScrollOffset, 5 * 7, accuracy: 0.001)
        XCTAssertEqual(result.cards[0].markerY - nowY, 30 * 7, accuracy: 0.001, "The first train is on the first screen")
    }

    // MARK: Delay

    func testNineMinuteDelayDrawsASixtyThreePointBar() throws {
        let result = layout([delayed7_32(), train("b", 7, 58)], now: at(7, 21))
        let card = result.cards[0]
        let bar = try XCTUnwrap(card.delayBar)
        XCTAssertEqual(bar.upperBound - bar.lowerBound, 63, accuracy: 0.001)
        XCTAssertEqual(bar.upperBound, card.markerY, "The bar runs down to the expected marker")
        XCTAssertEqual(card.top, card.markerY - standard.anchor, "The card sits at the expected time")
        XCTAssertNil(result.cards[1].delayBar)
    }

    func testDelayOverThirtyMinutesIsNotFolded() throws {
        let late = train("b", 7, 32, status: .delayed(minutes: 40, reportedAt: at(7, 14)), expected: at(8, 12))
        let result = layout([train("a", 7, 25), late])
        let bar = try XCTUnwrap(result.cards[1].delayBar)
        XCTAssertEqual(bar.upperBound - bar.lowerBound, 40 * 7, accuracy: 0.001, "The bar's length is the delay")
        XCTAssertTrue(result.folds.isEmpty)
    }

    // MARK: Gridline labels, Now and the ends

    /// Every 15 min of wall-clock time gets a line, whatever the trains; the lines carry no train times (D49).
    func testGridlinesRunEveryFifteenMinutes() throws {
        let result = layout([train("a", 7, 32), train("b", 7, 58)], now: at(7, 21))
        let half = try gridline(result, 7, 30)
        let quarter = try gridline(result, 7, 45)
        _ = try gridline(result, 8, 0)
        XCTAssertEqual(half.y, result.cards[0].markerY - 14, accuracy: 0.001)
        XCTAssertEqual(quarter.y - half.y, 15 * 7, accuracy: 0.001)
    }

    func testInitialScrollPutsNowFiveMinutesBelowTheTop() throws {
        let result = layout([train("a", 7, 32), train("b", 7, 58)], now: at(7, 40))
        let nowY = try XCTUnwrap(result.nowY)
        XCTAssertEqual(nowY - result.initialScrollOffset, 5 * 7, accuracy: 0.001, "Now sits 5 min below the top edge (D49)")
        XCTAssertEqual(nowY - result.cards[0].markerY, 8 * 7, accuracy: 0.001, "Earlier trains stay above, reachable by scrolling")
        XCTAssertEqual(result.endOfServiceY, result.cards[1].bottom + TTTimeline.minCardGap, accuracy: 0.001)
        XCTAssertGreaterThan(result.height, result.endOfServiceY)
    }

    func testAnotherDayStartsAtTheFirstTrainWithNoNowLine() {
        let result = layout([train("a", 6, 10), train("b", 6, 40)])
        XCTAssertNil(result.nowY)
        XCTAssertEqual(result.initialScrollOffset, 0)
        XCTAssertEqual(result.cards[0].top, TTTimeline.minCardGap, accuracy: 0.001)
    }

    // MARK: Compact scale

    func testCompactScale() throws {
        let result = layout([delayed7_32(), train("b", 8, 5)], now: at(7, 21), scale: TTTimeline.pointsPerMinuteCompact)
        let bar = try XCTUnwrap(result.cards[0].delayBar)
        XCTAssertEqual(bar.upperBound - bar.lowerBound, 9 * 6, accuracy: 0.001)
        XCTAssertEqual(try gridline(result, 7, 45).y - gridline(result, 7, 30).y, 15 * 6, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(result.nowY) - result.initialScrollOffset, 5 * 6, accuracy: 0.001)
    }

    // MARK: Determinism and identity

    func testLayoutIsDeterministicAndKeyedByTrip() {
        let departures = [delayed7_32(), train("b", 7, 42), train("c", 8, 21), train("d", 9, 30)]
        let input = TimelineInput(departures: departures, now: at(7, 21))
        let shuffled = TimelineInput(departures: departures.reversed(), now: at(7, 21))
        XCTAssertEqual(TimelineLayout(input), TimelineLayout(input))
        XCTAssertEqual(TimelineLayout(input), TimelineLayout(shuffled))
        XCTAssertEqual(TimelineLayout(input).cards.map(\.id), departures.map(\.id))

        // A moving estimate keeps the card's identity (D9).
        var later = departures
        later[0] = train("LW-0732", 7, 32, status: .delayed(minutes: 11, reportedAt: at(7, 16)), expected: at(7, 43))
        XCTAssertEqual(layout(later, now: at(7, 21)).cards.map(\.id), [later[1].id, later[0].id, later[2].id, later[3].id])
    }
}
