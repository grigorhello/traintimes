import ActivityKit
import AppIntents
import Foundation

/// Not on it on the Live Activity card (TT-243, D120): for a ride's first 10 min after it started by itself. It ends the
/// ride's card at once, without opening the app, and hands the ride to the app (`notOnIt`), which ends the ride, leaves that
/// train alone today and counts the tap toward two in 14 days. Compiled by the app and the widget extension (the button
/// needs the type); iOS runs a `LiveActivityIntent` in the app's process, where `AppDelegate` sets `notOnIt` at launch.
struct NotOnTrainIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "onboard.notOnIt"
    static let isDiscoverable = false

    @Parameter(title: "Trip") var tripId: String
    @Parameter(title: "Service date") var serviceDate: Int
    @Parameter(title: "From") var originId: String
    @Parameter(title: "To") var destinationId: String

    init() {}

    init(_ attributes: RideActivityAttributes) {
        tripId = attributes.tripId
        serviceDate = attributes.serviceDate
        originId = attributes.originId
        destinationId = attributes.destinationId
    }

    /// The app's handler: set by `AppDelegate` at launch; nil in the extension.
    @MainActor static var notOnIt: (@MainActor (DeclinedDeparture) -> Void)?

    func perform() async throws -> some IntentResult {
        let train = DeclinedDeparture(tripId: tripId, serviceDate: serviceDate, originId: originId, destinationId: destinationId)
        for activity in Activity<RideActivityAttributes>.activities
        where activity.attributes.shows(
            tripId: train.tripId, serviceDate: train.serviceDate, originId: train.originId, destinationId: train.destinationId
        ) {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        await MainActor.run { Self.notOnIt?(train) }
        return .result()
    }
}
