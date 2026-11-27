import ActivityKit
import SwiftUI
import WidgetKit

/// The widget extension (TT-174, TT-181): the On board Live Activity and the widgets, Next train (Home Screen, StandBy and
/// the Lock Screen, TT-184) and Departures (TT-183).
@main
struct TrainTimesWidgets: WidgetBundle {
    var body: some Widget {
        RideActivityWidget()
        NextTrainWidget()
        DeparturesWidget()
    }
}

/// The ride on the Lock Screen and in the Dynamic Island, and before it the alerted train's countdown: one card for every
/// moment (TT-205, D93; boards 3, 12, 13 and 15 of the Live view canvas). A tap anywhere opens Trip details on the ride (on
/// the train before departure), where "I’m on board" and End ride are. Its only buttons are the departure question's Yes
/// and No once an alerted train has left (TT-231, D110). iOS does not grey a stale activity, so the views do (`isStale`).
struct RideActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RideActivityAttributes.self) { context in
            RideActivityLockView(attributes: context.attributes, state: context.state, isStale: context.isStale)
                .activityBackgroundTint(RideActivityLockView.background(context.state, isStale: context.isStale))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(Self.link(context.state, isStale: context.isStale).url)
        } dynamicIsland: { context in
            let attributes = context.attributes
            let state = context.state
            let style = RideActivityStyle.island(state, isStale: context.isStale)
            return DynamicIsland {
                // The card under the camera, the full width; the island stays black (iOS draws it so).
                DynamicIslandExpandedRegion(.bottom) {
                    RideActivityExpanded(attributes: attributes, state: state, style: style)
                }
            } compactLeading: {
                RideActivityCompactLeading(attributes: attributes, state: state, style: style)
            } compactTrailing: {
                RideActivityCompactTrailing(state: state, style: style)
            } minimal: {
                RideActivityMinimal(attributes: attributes, state: state, isStale: context.isStale)
            }
            .keylineTint(Self.keyline(state, isStale: context.isStale))
            .widgetURL(Self.link(state, isStale: context.isStale).url)
        }
    }

    /// A tap opens the ride, or before departure the train's Trip details; while the card warns of a wrong train, the app
    /// on the warning (TT-250, D127), except on a stale card, which draws the plain card.
    static func link(_ state: RideActivityAttributes.ContentState, isStale: Bool = false) -> RideActivityLink {
        if state.wrong != nil, !isStale { return .wrong }
        return state.isDeparture ? .departure : .open
    }

    /// The island's keyline: amber while it warns of a wrong train, mint once close or asking, else faint white.
    static func keyline(_ state: RideActivityAttributes.ContentState, isStale: Bool) -> Color {
        if state.wrong != nil, !isStale { return RideActivityStyle.amber }
        return state.isClose || state.isAsking ? RideActivityStyle.mint : .white.opacity(0.3)
    }
}
