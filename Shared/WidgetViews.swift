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
            // The row is 38 pt high and a 34 pt line is taller: offered that height, a text that may shrink would
            // shrink to fit it. Its own height keeps it at 34 pt; it still shrinks for width ("11:47 PM" and the bolt).
            Text(verbatim: train.time.digits)
                .font(TTFont.timeLead)
                .tracking(-0.8)
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.numericText())
            if let period = train.time.period {
                Text(verbatim: period)
                    .font(TTFont.widgetPeriod)
                    .tracking(-0.3)
                    .fixedSize()
            }
            if train.isExpress {
                // Level with the middle of the digits, as on the board, not on their baseline.
                Image(systemName: "bolt.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(TTColor.accent)
                    .widgetAccentable()
                    .padding(.leading, 3)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 12 }
            }
        }
        .foregroundStyle(TTColor.ink)
        .lineLimit(1)
        .frame(height: 38)
        .padding(.top, train.isYourTrain ? 0 : 13)

        countdown(train)
            .font(TTFont.widgetCountdown)
            .tracking(-0.3)
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

    /// "in 11 min", "Last train · 32 min" or "now".
    @ViewBuilder
    private func countdown(_ train: NextTrainContent.Train) -> some View {
        if train.isLeavingNow {
            Text("widget.now")
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if train.isLastTrain {
                    Text("widget.last_train").fixedSize()
                    Text(verbatim: "·").fixedSize()
                } else {
                    Text("widget.in").fixedSize()
                }
                Text(verbatim: train.countdown)
                    .contentTransition(.numericText())
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
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
        .tracking(-0.1)
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
                .tracking(-0.4)
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
                    Text(verbatim: train.time)
                        .font(TTFont.widgetTime)
                        .tracking(-0.8)
                        .monospacedDigit()
                        .foregroundStyle(TTColor.ink)
                        .contentTransition(.numericText())
                        .fixedSize()
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
                    // Proportional digits (the countdown is not a clock time), a point into the margin as on the board,
                    // so "11 min" starts under the departure time.
                    // A three-digit wait beside two 24-hour times shrinks rather than end in dots. It shrinks for width
                    // only: the row is 46 pt high and a 44 pt line is taller, so the text keeps its own height.
                    hero(train)
                        .font(TTFont.widgetHero)
                        .tracking(-1.4)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, -1)
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

    /// "11 min" in accent; "now" in the last minute.
    @ViewBuilder
    private func hero(_ train: DeparturesContent.Train) -> some View {
        if train.isLeavingNow {
            Text("widget.now")
                .foregroundStyle(TTColor.accent)
                .widgetAccentable()
        } else {
            Text(verbatim: train.countdown)
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
