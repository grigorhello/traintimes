import Foundation
@testable import TrainTimes

/// Train detection's states for the strip, question and snapshot tests (TT-175): the demo's 5:13 PM Lakeshore West train
/// from Union on Friday, Nov 27, and a 5:16 PM express beside it for the two-train question.
enum DetectionFixtures {
    static let day = OnBoardFixtures.friday
    static var train: TrainCandidate { DemoRide.candidate(on: day) }

    /// The demo train 3 min later, as another trip: the timetable cannot tell the two apart.
    static var express: TrainCandidate {
        let plan = DemoRide.plan(on: day)
        let shifted = RidePlan(
            stops: plan.stops.map {
                RidePlan.Stop(station: $0.station, arrival: $0.arrival.addingTimeInterval(180), departure: $0.departure.addingTimeInterval(180))
            },
            track: plan.track
        )
        return TrainCandidate(trip: TripKey(serviceDay: day, tripId: "DEMO-LW-1716"), route: DemoRide.route, plan: shifted)
    }

    /// "Moving along Lakeshore West": no shared stop yet (`stops` 0), or the train with one or two.
    static func progress(stops: Int) -> TrainMatcher.Progress {
        TrainMatcher.Progress(line: DemoRide.line, since: train.plan.stops[0].station, train: stops > 0 ? train : nil, stops: stops)
    }

    /// "On the 5:13 PM train?" after Exhibition and Mimico; with `both`, the 5:16 PM too.
    static func question(both: Bool = false) -> TrainMatcher.Question {
        let stops = train.plan.stops
        let trains = both ? [train, express] : [train]
        return TrainMatcher.Question(
            trains: trains,
            since: stops[0].station,
            stops: [stops[1].station, stops[2].station],
            askedAt: day.gtfsTime(17 * 3600 + 25 * 60 + 50),
            lastStop: 2,
            fitting: trains.map(\.trip)
        )
    }
}
