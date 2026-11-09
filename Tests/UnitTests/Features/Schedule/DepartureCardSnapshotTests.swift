import SnapshotTesting
import SwiftUI
import XCTest
@testable import TrainTimes

/// TT-157: every card state on the Card states canvas, light and dark, at the timeline's card width (82 pt in from the
/// left, 20 pt from the right). Page A: next on time, platform not published, departing, later on time, delayed with the
/// alert on, later delayed. Page B: cancelled, stop skipped, no live data, last reported, 24-hour, the widest case.
final class DepartureCardSnapshotTests: XCTestCase {
    @MainActor func testCardStatesALight() { snap(Self.pageA, .light) }
    @MainActor func testCardStatesADark() { snap(Self.pageA, .dark) }
    @MainActor func testCardStatesBLight() { snap(Self.pageB, .light) }
    @MainActor func testCardStatesBDark() { snap(Self.pageB, .dark) }

    private struct Sample {
        let card: DepartureCard
        var bell: AlertBellModel.Bell = .off
    }

    private static let day = ServiceDay(year: 2026, month: 11, day: 5)
    private static let twelve = TimeFormatter(format: .twelveHour)

    private static func sample(
        _ hour: Int, _ minute: Int, minutes: Int = 40, platform: Platform = .pending, express: Bool = false,
        status: TrainStatus = .onTime, delay: Int = 0, isNext: Bool = false, nowBefore: TimeInterval = 11 * 60,
        nextUsableBelow: Bool = true, formatter: TimeFormatter = twelve, bell: AlertBellModel.Bell = .off
    ) -> Sample {
        let departure = day.date(hour: hour, minute: minute)
        let trip = Trip(
            key: TripKey(serviceDay: day, tripId: "T\(hour)\(minute)\(minutes)\(delay)"),
            scheduledDeparture: departure,
            scheduledArrival: departure.addingTimeInterval(TimeInterval(minutes * 60)),
            platform: platform,
            tags: express ? [.express] : []
        )
        let shift = TimeInterval(delay * 60)
        let resolved = Departure(
            trip: trip,
            status: status,
            expectedDeparture: delay > 0 ? departure.addingTimeInterval(shift) : nil,
            expectedArrival: delay > 0 ? trip.scheduledArrival.addingTimeInterval(shift) : nil
        )
        let now = resolved.departureTime.addingTimeInterval(-nowBefore)
        let card = DepartureCard(resolved, isNext: isNext, nextUsableBelow: nextUsableBelow, now: now, formatter: formatter)
        return Sample(card: card, bell: bell)
    }

    private static var reported: Date { day.date(hour: 7, minute: 20) }

    private static var pageA: [Sample] {
        [
            sample(7, 58, platform: .published("2"), express: true, isNext: true),
            sample(7, 58, isNext: true),
            sample(7, 58, platform: .published("2"), express: true, isNext: true, nowBefore: 30),
            sample(8, 21, minutes: 35, express: true),
            sample(7, 32, platform: .published("2"), status: .delayed(minutes: 9, reportedAt: reported), delay: 9,
                   isNext: true, nowBefore: 20 * 60, bell: .on),
            sample(8, 28, express: true, status: .delayed(minutes: 5, reportedAt: reported), delay: 5),
        ]
    }

    private static var pageB: [Sample] {
        [
            sample(17, 28, status: .cancelled(reportedAt: reported)),
            sample(7, 32, status: .stopSkipped),
            sample(9, 47, minutes: 46, status: .scheduled),
            sample(7, 58, express: true, status: .stale(lastReported: reported)),
            sample(17, 10, platform: .published("4"), express: true, isNext: true, formatter: TimeFormatter(format: .twentyFourHour)),
            sample(12, 32, minutes: 72, platform: .published("26"), express: true,
                   status: .delayed(minutes: 15, reportedAt: reported), delay: 15, bell: .on),
        ]
    }

    @MainActor
    private func snap(_ samples: [Sample], _ style: UIUserInterfaceStyle, testName: String = #function, line: UInt = #line) {
        let view = VStack(spacing: TTSpace.s3) {
            ForEach(Array(samples.enumerated()), id: \.offset) { item in
                DepartureCardView(card: item.element.card, bell: item.element.bell, onOpen: {}, onSize: { _ in })
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 82)
        .padding(.trailing, TTSpace.s5)
        .padding(.top, 60)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TTColor.canvas)
        assertSnapshot(
            of: view,
            as: .image(perceptualPrecision: 0.98, layout: .device(config: .iPhone17Pro), traits: UITraitCollection(userInterfaceStyle: style)),
            testName: testName,
            line: line
        )
    }
}
