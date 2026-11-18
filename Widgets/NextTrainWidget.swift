import AppIntents
import SwiftUI
import WidgetKit

/// Next train, small (TT-181, D101): a placeholder with one fixed entry, "Open Train Times once", until TT-183 draws the
/// real widget from the app's widget file (TT-182). Its gallery name and description are the final ones.
struct NextTrainWidget: Widget {
    static let kind = "NextTrain"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: NextTrainIntent.self, provider: NextTrainProvider()) { _ in
            NextTrainPlaceholderView()
                .containerBackground(TTColor.surface, for: .widget)
        }
        .configurationDisplayName("widget.next.name")
        .description("widget.next.description")
        .supportedFamilies([.systemSmall])
    }
}

/// The widget's settings; empty until TT-183 adds From, To and "Turn around at 12 PM".
struct NextTrainIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "widget.next.name"
}

struct NextTrainEntry: TimelineEntry {
    let date: Date
}

struct NextTrainProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> NextTrainEntry {
        NextTrainEntry(date: .now)
    }

    func snapshot(for configuration: NextTrainIntent, in context: Context) async -> NextTrainEntry {
        NextTrainEntry(date: .now)
    }

    func timeline(for configuration: NextTrainIntent, in context: Context) async -> Timeline<NextTrainEntry> {
        Timeline(entries: [NextTrainEntry(date: .now)], policy: .never)
    }
}

/// The small "Not loaded yet" state of the Widgets-States board, in tokens.
struct NextTrainPlaceholderView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: TTSpace.s1) {
            Spacer(minLength: 0)
            Text("widget.not_loaded.title")
                .font(TTFont.headline)
                .foregroundStyle(TTColor.ink)
            Text("widget.not_loaded.body")
                .font(TTFont.subhead)
                .foregroundStyle(TTColor.inkSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
