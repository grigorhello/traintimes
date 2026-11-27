import ActivityKit
import AppIntents
import Foundation

/// "I’m fine" on the wrong train warning's card (TT-250, D127), on the Lock Screen and in the expanded island alike. Unlike
/// Not on it it keeps a ride's card: the warning goes from it (its stale date kept) without opening the app, and the app's
/// handler (`fine`, which `AppDelegate` sets at launch) takes the warning away and keeps the train from warning again
/// today. A departure card (TT-251's case) it ends, as No does: the server never follows a handed-off card again. Compiled
/// by the app and the widget extension (the button needs the type); iOS runs a `LiveActivityIntent` in the app's process,
/// and can launch the app cold for it.
struct WrongTrainFineIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "wrong.fine"
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
    @MainActor static var fine: (@MainActor (DeclinedDeparture) -> Void)?

    func perform() async throws -> some IntentResult {
        let train = DeclinedDeparture(tripId: tripId, serviceDate: serviceDate, originId: originId, destinationId: destinationId)
        for activity in Activity<RideActivityAttributes>.activities
        where activity.attributes.shows(
            tripId: train.tripId, serviceDate: train.serviceDate, originId: train.originId, destinationId: train.destinationId
        ) {
            var state = activity.content.state
            if state.isDeparture {
                await activity.end(nil, dismissalPolicy: .immediate)
            } else {
                state.wrong = nil
                await activity.update(ActivityContent(state: state, staleDate: activity.content.staleDate))
            }
        }
        await MainActor.run { Self.fine?(train) }
        return .result()
    }
}
