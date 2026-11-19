import ActivityKit
import SwiftUI
import WidgetKit

/// The widget extension (TT-174, TT-181): the On board Live Activity and the Home Screen widgets, Next train and
/// Departures (TT-183).
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
/// the train before departure), where "I’m on board" and End ride are; the card has no buttons. iOS does not grey a stale
/// activity, so the views do (`isStale`).
struct RideActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RideActivityAttributes.self) { context in
            RideActivityLockView(attributes: context.attributes, state: context.state, isStale: context.isStale)
                .activityBackgroundTint(RideActivityLockView.background(context.state))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(Self.link(context.state).url)
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
                RideActivityTile(attributes: attributes, size: .minimal)
            }
            .keylineTint(state.isClose ? RideActivityStyle.mint : .white.opacity(0.3))
            .widgetURL(Self.link(state).url)
        }
    }

    /// A tap opens the ride, or before departure the train's Trip details.
    static func link(_ state: RideActivityAttributes.ContentState) -> RideActivityLink {
        state.isDeparture ? .departure : .open
    }
}
