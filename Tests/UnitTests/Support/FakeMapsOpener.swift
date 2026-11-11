@testable import TrainTimes

/// Records the Directions taps instead of opening Apple Maps (TT-188).
@MainActor
final class FakeMapsOpener: MapsOpening {
    struct Opened: Equatable {
        let name: String
        let place: GeoPoint
    }

    private(set) var opened: [Opened] = []

    func openDirections(to name: String, at place: GeoPoint) {
        opened.append(Opened(name: name, place: place))
    }
}
