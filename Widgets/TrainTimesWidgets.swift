import ActivityKit
import SwiftUI
import WidgetKit

/// The widget extension (TT-174): the On board Live Activity for now; the Home and Lock Screen widgets (TT-181 onward) join
/// this bundle.
@main
struct TrainTimesWidgets: WidgetBundle {
    var body: some Widget {
        RideActivityWidget()
    }
}

/// The ride on the Lock Screen and in the Dynamic Island (*Live-Lock*, *Live-Island*, D67), and before it the alerted
/// train's countdown (*Live-Depart-Lock*, TT-178, D74). A tap anywhere opens Trip details on the ride (on the train before
/// departure); the expanded island's End ride, or "I’m on board" before departure, is a link, the one control Apple lets
/// work there. iOS does not grey a stale activity, so the views do (`isStale`).
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
                // Arriving: the green card fills the island under the camera (the bottom region, the full width); otherwise
                // the Lock Screen layout around the camera.
                DynamicIslandExpandedRegion(.leading) {
                    if !state.isAlert {
                        RideActivityTile(attributes: attributes, size: .large, edge: style.tileEdge)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if state.isDeparture {
                        RideActivityDepartureCountdown(state: state, style: style)
                    } else if !state.isAlert {
                        RideActivityCountdownStack(state: state, style: style)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    if state.isDeparture {
                        RideActivityDepartureTitle(attributes: attributes, state: state, style: style)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if !state.isAlert {
                        RideActivityTitle(state: state, style: style)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if state.isDeparture {
                        RideActivityDepartureBottom(state: state, style: style)
                    } else if state.isAlert {
                        RideActivityExpandedAlert(attributes: attributes, state: state, style: style)
                    } else {
                        RideActivityExpandedBottom(attributes: attributes, state: state, style: style)
                    }
                }
            } compactLeading: {
                RideActivityTile(attributes: attributes, size: .compact)
            } compactTrailing: {
                if state.isDeparture {
                    RideActivityDepartureCompactTrailing(state: state, style: style)
                } else {
                    RideActivityCompactTrailing(state: state, style: style)
                }
            } minimal: {
                RideActivityTile(attributes: attributes, size: .minimal)
            }
            .keylineTint(state.isAlert ? RideActivityStyle.alertGreen : state.late ? RideActivityStyle.amber : RideActivityStyle.mint)
            .widgetURL(Self.link(state).url)
        }
    }

    /// A tap opens the ride, or before departure the train's Trip details.
    static func link(_ state: RideActivityAttributes.ContentState) -> RideActivityLink {
        state.isDeparture ? .departure : .open
    }
}
