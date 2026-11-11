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

/// The ride on the Lock Screen and in the Dynamic Island (*Live-Lock*, *Live-Island*, D67). A tap anywhere opens Trip
/// details on the ride; the expanded island's End ride is a link, the one control Apple lets work there. iOS does not grey
/// a stale activity, so the views do (`isStale`).
struct RideActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RideActivityAttributes.self) { context in
            RideActivityLockView(attributes: context.attributes, state: context.state, isStale: context.isStale)
                .activityBackgroundTint(RideActivityLockView.background(context.state))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(RideActivityLink.open.url)
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
                    if !state.isAlert {
                        RideActivityCountdownStack(state: state, style: style)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    if !state.isAlert {
                        RideActivityTitle(state: state, style: style)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if state.isAlert {
                        RideActivityExpandedAlert(attributes: attributes, state: state, style: style)
                    } else {
                        RideActivityExpandedBottom(attributes: attributes, state: state, style: style)
                    }
                }
            } compactLeading: {
                RideActivityTile(attributes: attributes, size: .compact)
            } compactTrailing: {
                RideActivityCompactTrailing(state: state, style: style)
            } minimal: {
                RideActivityTile(attributes: attributes, size: .minimal)
            }
            .keylineTint(state.isAlert ? RideActivityStyle.alertGreen : RideActivityStyle.mint)
            .widgetURL(RideActivityLink.open.url)
        }
    }
}
