import SwiftUI
import WidgetKit

// The Home Screen widgets' views (TT-183; boards Widgets-States and Widgets-Home-Lean of the Widgets canvas), in `Shared/`
// so the app's unit tests snapshot what the extension draws. Tokens only; every word comes from `NextTrainContent` and
// `DeparturesContent`.

/// How iOS shows the widget where it takes its colours or its background away; the extension's wrapper reads
/// `widgetRenderingMode` and `showsWidgetContainerBackground` and passes them on.
struct WidgetLook: Equatable, Sendable {
    /// False on a tinted or clear Home Screen: iOS draws the widget in one colour, so the line tile is an outline.
    var isFullColor = true
    /// False where iOS removes the background (StandBy, a tinted or clear Home Screen).
    var showsBackground = true
}

extension EnvironmentValues {
    @Entry var widgetLook = WidgetLook()
    /// A fixed moment for the countdown: snapshot tests and the gallery's sample draw "11 min" from it, not from the clock.
    @Entry var widgetCountdownFixedAt: Date? = nil
    /// False before iOS 18, where no text counts down by itself: the widgets show the clock time only.
    @Entry var widgetShowsCountdown: Bool = WidgetCountdown.isAvailable
}

/// The minutes to a departure, "11 min", the one view that counts down (TT-183). On iOS 18 and later iOS redraws the text
/// each minute by itself, with no timeline entry or reload; the last minute is the widget's own "now" (an entry of its
/// own, `WidgetEntryBuilder.leavingLead`). The unit is iOS's abbreviation, kept at "min" as the app writes it (Canadian
/// English would say "mins").
struct WidgetCountdown: View {
    let departure: Date
    @Environment(\.widgetCountdownFixedAt) private var fixedAt

    static var isAvailable: Bool {
        if #available(iOS 18, *) { true } else { false }
    }

    private static let unitLocale = Locale(identifier: "en_US")

    /// Whole minutes, rounded down: "11 min", "187 min", never hours or seconds.
    private static var format: Date.ComponentsFormatStyle {
        Date.ComponentsFormatStyle.components(style: .abbreviated, fields: [.minute]).locale(unitLocale)
    }

    var body: some View {
        if let fixedAt {
            Text(verbatim: Self.minutes(from: fixedAt, to: departure))
        } else if #available(iOS 18, *) {
            // In a widget this text takes the width it is offered, so its container places it.
            Text(.dateRange(endingAt: departure), format: Self.format)
                .multilineTextAlignment(.leading)
                .environment(\.locale, Self.unitLocale)
        }
    }

    /// The same words at a fixed moment: whole minutes left, rounded down like iOS's.
    static func minutes(from now: Date, to departure: Date) -> String {
        String(format: String(localized: "widget.minutes"), max(0, Int(departure.timeIntervalSince(now) / 60)))
    }
}

/// A message's second line, its time strong.
private struct WidgetMessageDetail: View {
    let text: WidgetText
    let font: Font
    let strongFont: Font

    var body: some View {
        Text(attributed)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var attributed: AttributedString {
        var result = AttributedString()
        for piece in text.pieces {
            var run = AttributedString(piece.text)
            run.font = piece.isStrong ? strongFont : font
            run.foregroundColor = piece.isStrong ? TTColor.ink : TTColor.inkSecondary
            result += run
        }
        return result
    }
}

// MARK: - Next train, small

/// Next train (158 pt square): the line tile and "to Union", the time, the countdown in accent, and one footer line.
struct NextTrainWidgetView: View {
    let content: NextTrainContent
    @Environment(\.widgetLook) private var look
    @Environment(\.widgetShowsCountdown) private var showsCountdown

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let header = content.header {
                self.header(header)
            }
            switch content.body {
            case .train(let train):
                self.train(train)
            case .message(let message):
                self.message(message)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(EdgeInsets(top: 14, leading: 15, bottom: 13, trailing: 14))
    }

    private func header(_ header: WidgetHeaderContent) -> some View {
        HStack(spacing: 7) {
            if let line = header.line {
                LineTile(line: line, kind: .widgetSmall, isOutline: !look.isFullColor)
                    .widgetAccentable(!look.isFullColor)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("widget.to")
                    .font(TTFont.widgetTo)
                    .foregroundStyle(TTColor.inkSecondary)
                    .fixedSize()
                Text(verbatim: header.to)
                    .font(TTFont.widgetStation)
                    .foregroundStyle(TTColor.ink)
                    .minimumScaleFactor(0.7)
            }
            .tracking(-0.2)
            .lineLimit(1)
        }
        .frame(height: 20)
    }

    @ViewBuilder
    private func train(_ train: NextTrainContent.Train) -> some View {
        if train.isYourTrain {
            HStack(spacing: 4) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text("widget.your_train")
                    .font(TTFont.widgetYourTrain)
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(TTColor.accent)
            .widgetAccentable()
            .padding(.top, 11)
        }
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(verbatim: train.time.digits)
                .font(TTFont.timeLead)
                .tracking(-0.8)
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
            if let period = train.time.period {
                Text(verbatim: period)
                    .font(TTFont.widgetPeriod)
                    .fixedSize()
            }
            if train.isExpress {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(TTColor.accent)
                    .widgetAccentable()
                    .padding(.leading, 3)
            }
        }
        .foregroundStyle(TTColor.ink)
        .lineLimit(1)
        .frame(height: 38)
        .padding(.top, train.isYourTrain ? 0 : 13)

        countdown(train)
            .font(TTFont.widgetCountdown)
            .foregroundStyle(TTColor.accent)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .widgetAccentable()
            .frame(height: 21)
            .padding(.top, 1)
            // "Last train · 32 min" is the board's widest line: it may run 8 pt into the right margin.
            .padding(.trailing, -8)

        Spacer(minLength: 0)
        if let footer = train.footer {
            self.footer(footer)
        }
    }

    /// "in 11 min", "Last train · 32 min" or "now"; before iOS 18 nothing, or "Last train" alone.
    @ViewBuilder
    private func countdown(_ train: NextTrainContent.Train) -> some View {
        if train.isLeavingNow {
            Text("widget.now")
        } else if showsCountdown {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if train.isLastTrain {
                    Text("widget.last_train").fixedSize()
                    Text(verbatim: "·").fixedSize()
                } else {
                    Text("widget.in").fixedSize()
                }
                WidgetCountdown(departure: train.departure)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if train.isLastTrain {
            Text("widget.last_train")
        } else {
            Color.clear
        }
    }

    private func footer(_ footer: NextTrainContent.Footer) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(Self.label(footer.label))
                .font(TTFont.footnote)
                .foregroundStyle(TTColor.inkSecondary)
            Text(verbatim: footer.time)
                .font(TTFont.widgetFooterTime)
                .monospacedDigit()
                .foregroundStyle(TTColor.ink)
            switch footer.mark {
            case .express:
                Image(systemName: "bolt.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(TTColor.accent)
                    .widgetAccentable()
            case .alert:
                Image(systemName: "bell.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(TTColor.accent)
                    .widgetAccentable()
            case nil:
                EmptyView()
            }
        }
        .lineLimit(1)
        .fixedSize()
    }

    private static func label(_ label: NextTrainContent.Footer.Label) -> LocalizedStringKey {
        switch label {
        case .then: "widget.then"
        case .earlier: "widget.earlier"
        case .first: "widget.first"
        }
    }

    private func message(_ message: WidgetMessage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: message.title)
                .font(TTFont.headline)
                .tracking(-0.3)
                .foregroundStyle(TTColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let detail = message.detail {
                WidgetMessageDetail(text: detail, font: TTFont.footnote, strongFont: TTFont.widgetFooterTime)
            }
        }
        .padding(.top, 12)
    }
}

// MARK: - Departures, medium

/// Departures (338 × 158 pt): the route, the next train's departure over its countdown, its arrival, and the two trains
/// after it on one line. Three sizes only: 44, 28 and 15 pt.
struct DeparturesWidgetView: View {
    let content: DeparturesContent
    @Environment(\.widgetLook) private var look
    @Environment(\.widgetShowsCountdown) private var showsCountdown

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let header = content.header {
                self.header(header)
            }
            Spacer(minLength: 0)
            switch content.body {
            case .train(let train):
                self.train(train)
            case .message(let message):
                self.message(message)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 13, trailing: 16))
    }

    private func header(_ header: WidgetHeaderContent) -> some View {
        HStack(spacing: 8) {
            if let line = header.line {
                LineTile(line: line, kind: .widget, isOutline: !look.isFullColor)
                    .widgetAccentable(!look.isFullColor)
            }
            HStack(spacing: 5) {
                Text(verbatim: header.from)
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(TTColor.inkTertiary)
                Text(verbatim: header.to)
            }
            .font(TTFont.widgetStrong)
            .tracking(-0.2)
            .foregroundStyle(TTColor.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .frame(height: 26)
    }

    private func train(_ train: DeparturesContent.Train) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // The next train's block opens its Trip details: the departure and the arrival, level with each other.
            Link(destination: train.link) {
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    if showsCountdown {
                        Text(verbatim: train.time)
                            .font(TTFont.widgetTime)
                            .tracking(-0.8)
                            .monospacedDigit()
                            .foregroundStyle(TTColor.ink)
                            .contentTransition(.numericText())
                            .fixedSize()
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("widget.arrives")
                            .font(TTFont.widgetLabel)
                        Text(verbatim: train.arrival)
                            .font(TTFont.widgetArrival)
                            .tracking(-0.8)
                            .monospacedDigit()
                            .frame(height: 32)
                    }
                    .foregroundStyle(TTColor.inkSecondary)
                    .fixedSize()
                }
            }
            // The countdown, and on its baseline the trains after it.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Link(destination: train.link) {
                    hero(train)
                        .font(TTFont.widgetHero)
                        .tracking(-1.4)
                        .monospacedDigit()
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !train.later.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("widget.next")
                            .font(TTFont.widgetLabel)
                            .foregroundStyle(TTColor.inkSecondary)
                        ForEach(train.later) { later in
                            Link(destination: later.link) {
                                Text(verbatim: later.time)
                                    .font(TTFont.widgetStrong)
                                    .monospacedDigit()
                                    .foregroundStyle(TTColor.ink)
                            }
                        }
                    }
                    .lineLimit(1)
                    .fixedSize()
                }
            }
            .frame(height: 46)
        }
    }

    /// "11 min" in accent, "now" in the last minute; before iOS 18 the departure time, in ink.
    @ViewBuilder
    private func hero(_ train: DeparturesContent.Train) -> some View {
        if !showsCountdown {
            Text(verbatim: train.time)
                .foregroundStyle(TTColor.ink)
        } else if train.isLeavingNow {
            Text("widget.now")
                .foregroundStyle(TTColor.accent)
                .widgetAccentable()
        } else {
            WidgetCountdown(departure: train.departure)
                .foregroundStyle(TTColor.accent)
                .contentTransition(.numericText())
                .widgetAccentable()
        }
    }

    private func message(_ message: WidgetMessage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: message.title)
                .font(TTFont.widgetTitle)
                .tracking(-0.6)
                .foregroundStyle(TTColor.ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if let detail = message.detail {
                WidgetMessageDetail(text: detail, font: TTFont.widgetLabel, strongFont: TTFont.widgetStrong)
            }
        }
    }
}
