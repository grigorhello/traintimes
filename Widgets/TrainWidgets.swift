import AppIntents
import SwiftUI
import WidgetKit

/// Next train, small (TT-183, D101): the next train on the widget's route, how long until it leaves and the one after it,
/// on the Home Screen and in StandBy.
struct NextTrainWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetKind.nextTrain.kind, intent: TrainWidgetIntent.self, provider: TrainWidgetProvider()) {
            TrainWidgetEntryView(entry: $0, widget: .nextTrain)
        }
        .configurationDisplayName("widget.next.name")
        .description("widget.next.description")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
        .awayFromCarPlay(.systemSmall)
    }
}

/// Departures, medium (TT-183, revised Nov 13): the next train with its arrival, and the two after it.
struct DeparturesWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetKind.departures.kind, intent: TrainWidgetIntent.self, provider: TrainWidgetProvider()) {
            TrainWidgetEntryView(entry: $0, widget: .departures)
        }
        .configurationDisplayName("widget.departures.name")
        .description("widget.departures.description")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

private extension WidgetConfiguration {
    /// CarPlay shows small widgets from iOS 26: a train countdown has no place on the dashboard, so iOS is told to keep
    /// this one off it.
    func awayFromCarPlay(_ family: WidgetFamily) -> some WidgetConfiguration {
        if #available(iOS 26.0, *) {
            return disfavoredLocations([.carPlay], for: [family])
        } else {
            return self
        }
    }
}

/// One moment of either widget: TT-182's entry, and whether it is the gallery's fixed sample.
struct TrainWidgetEntry: TimelineEntry {
    let entry: WidgetEntry
    var isSample = false

    var date: Date { entry.date }

    var relevance: TimelineEntryRelevance? {
        TimelineEntryRelevance(score: Float(entry.relevance))
    }

    /// The gallery and the placeholder: the fixed sample, 7:58 AM from Oakville to Union in 11 min.
    static let sample = TrainWidgetEntry(entry: .sample, isSample: true)
}

/// Both widgets' timeline (TT-183): the widget file as the app last wrote it (TT-182), the widget's From and To (none
/// follows the route open in the app) and "Turn around at 12 PM", as TT-182's entries until 3 AM, when iOS asks again.
/// The real clock and the real timetable, never Settings › Testing.
struct TrainWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TrainWidgetEntry {
        .sample
    }

    func snapshot(for configuration: TrainWidgetIntent, in context: Context) async -> TrainWidgetEntry {
        context.isPreview ? .sample : entries(for: configuration).entries.first.map { TrainWidgetEntry(entry: $0) } ?? .sample
    }

    func timeline(for configuration: TrainWidgetIntent, in context: Context) async -> Timeline<TrainWidgetEntry> {
        let timeline = entries(for: configuration)
        return Timeline(entries: timeline.entries.map { TrainWidgetEntry(entry: $0) }, policy: .after(timeline.reloadAt))
    }

    private func entries(for configuration: TrainWidgetIntent) -> WidgetTimeline {
        let file = WidgetFile.containerFileURL.flatMap { WidgetFile.read(from: $0) }
        return WidgetEntryBuilder.timeline(file: file, route: configuration.route, turnsAround: configuration.turnsAround, now: .now)
    }
}

/// The widget on screen: its view from `Shared/`, told how iOS shows it here (in one colour on a tinted or clear Home
/// Screen, without its background in StandBy), on the surface colour, with its tap.
struct TrainWidgetEntryView: View {
    let entry: TrainWidgetEntry
    let widget: WidgetKind
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.showsWidgetContainerBackground) private var showsBackground

    var body: some View {
        content
            .environment(\.widgetLook, WidgetLook(isFullColor: renderingMode == .fullColor, showsBackground: showsBackground))
            .environment(\.widgetCountdownFixedAt, entry.isSample ? entry.date : nil)
            .containerBackground(TTColor.surface, for: .widget)
    }

    @ViewBuilder
    private var content: some View {
        switch widget {
        case .nextTrain:
            let model = NextTrainContent(entry.entry)
            NextTrainWidgetView(content: model)
                .widgetURL(model.link)
        case .departures:
            let model = DeparturesContent(entry.entry)
            DeparturesWidgetView(content: model)
                .widgetURL(model.link)
        }
    }
}
