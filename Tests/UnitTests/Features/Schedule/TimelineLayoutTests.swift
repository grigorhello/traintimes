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
        let result = layout(departures, now: repo.now)

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
        XCTAssertEqual(fold.minutes, 60)
        XCTAssertEqual(fold.next, at(18, 10))
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

    // MARK: Gridline labels, Now and the ends

    func testGridlineLabelHidesNearAPill() throws {
        let result = layout([train("a", 7, 32), train("b", 7, 58)], now: at(7, 21))
        let half = try gridline(result, 7, 30)
        let quarter = try gridline(result, 7, 45)
        let eight = try gridline(result, 8, 0)
        XCTAssertFalse(half.showsLabel, "7:30 is 14 pt from the 7:32 pill; the line stays")
        XCTAssertEqual(half.y, result.cards[0].markerY - 14, accuracy: 0.001)
        XCTAssertTrue(quarter.showsLabel)
        XCTAssertFalse(eight.showsLabel)
        XCTAssertEqual(quarter.y - half.y, 15 * 7, accuracy: 0.001)
    }

    func testInitialScrollPutsNowTwoMinutesBelowTheTop() throws {
        let result = layout([train("a", 7, 32), train("b", 7, 58)], now: at(7, 40))
        let nowY = try XCTUnwrap(result.nowY)
        XCTAssertEqual(nowY - result.initialScrollOffset, 14, accuracy: 0.001)
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
        XCTAssertEqual(try XCTUnwrap(result.nowY) - result.initialScrollOffset, 2 * 6, accuracy: 0.001)
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
