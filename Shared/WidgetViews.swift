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

/// Next train (164 pt square on the iPhone 17 Pro; the boards drew 158): the line tile and "to Union", the time, the
/// countdown in accent, and one footer line.
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

        Group {
            if let day = train.day {
                // My trains (TT-257, D131): "Monday" in the countdown's place while the saved train is more than 2 h away.
                Text(verbatim: day)
                    .foregroundStyle(TTColor.inkSecondary)
            } else {
                countdown(train)
                    .foregroundStyle(TTColor.accent)
                    .widgetAccentable()
            }
        }
        .font(TTFont.widgetCountdown)
        .tracking(-0.3)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(height: 21)
        .padding(.top, 1)
        // "Last train · 2 h 30 min" is the widest line: it may run 8 pt into the right margin.
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
            WidgetNowText(isTinted: !look.isFullColor)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if train.isLastTrain {
                    Text("widget.last_train").fixedSize()
                    Text(verbatim: "·").fixedSize()
                } else {
                    Text("widget.in").fixedSize()
                }
                // "Last train · 2 h 30 min" (TT-246, D123: hours from 60 min) is the widest line: the countdown alone may
                // shrink a little further than the rest of the line rather than end in dots.
                Text(verbatim: train.countdown)
                    .minimumScaleFactor(0.7)
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

/// Departures (350 × 164 pt on the iPhone 17 Pro; the boards drew 338 × 158), TT-257, D131 (board "Commute first" 6):
/// two train rows, each the route with its line tile and a saved train's bell, the minutes or the day at the right, and the
/// time with its arrival; or one row and "Next" with the trains after it. A message keeps TT-183's layout.
struct DeparturesWidgetView: View {
    let content: DeparturesContent
    @Environment(\.widgetLook) private var look

    var body: some View {
        switch content.body {
        case .rows(let rows):
            self.rows(rows)
        case .message(let message):
            VStack(alignment: .leading, spacing: 0) {
                if let header = content.header {
                    self.header(header)
                }
                Spacer(minLength: 0)
                self.message(message)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(EdgeInsets(top: 14, leading: 16, bottom: 13, trailing: 16))
        }
    }

    // MARK: Rows

    private func rows(_ rows: DeparturesContent.Rows) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            row(rows.first)
            Spacer(minLength: 0)
            switch rows.second {
            case .row(let row):
                VStack(alignment: .leading, spacing: 0) {
                    hairline
                    self.row(row)
                        .padding(.top, 8)
                }
            case .next(let later):
                VStack(alignment: .leading, spacing: 0) {
                    hairline
                    next(later)
                        .padding(.top, 23)
                    Spacer(minLength: 0)
                }
                .frame(height: 54)
            case nil:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(EdgeInsets(top: 12, leading: 16, bottom: 11, trailing: 16))
    }

    private var hairline: some View {
        Rectangle()
            .fill(TTColor.hairline)
            .frame(height: 1)
    }

    /// One train: the route and the minutes over the time and its arrival. The row opens the train's Trip details.
    private func row(_ row: DeparturesContent.Row) -> some View {
        Link(destination: row.link) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    if let line = row.header.line {
                        LineTile(line: line, kind: .widgetSmall, isOutline: !look.isFullColor)
                            .widgetAccentable(!look.isFullColor)
                    }
                    HStack(spacing: 5) {
                        Text(verbatim: row.header.from)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(TTColor.inkTertiary)
                        Text(verbatim: row.header.to)
                    }
                    .font(TTFont.widgetStrong)
                    .tracking(-0.2)
                    .foregroundStyle(TTColor.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    if row.isSaved {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(TTColor.accent)
                            .widgetAccentable()
                    }
                    Spacer(minLength: 4)
                    when(row)
                        .font(TTFont.widgetStrong)
                        .tracking(-0.2)
                        .lineLimit(1)
                        .fixedSize()
                }
                .frame(height: 22)
                HStack(alignment: .lastTextBaseline, spacing: 0) {
                    Text(verbatim: row.time.digits)
                        .font(TTFont.widgetTime)
                        .tracking(-0.8)
                        .monospacedDigit()
                        .foregroundStyle(TTColor.ink)
                    if let period = row.time.period {
                        Text(verbatim: period)
                            .font(TTFont.widgetStrong)
                            .foregroundStyle(TTColor.ink)
                            .padding(.leading, 3)
                    }
                    if row.isExpress {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(TTColor.accent)
                            .widgetAccentable()
                            .padding(.leading, 4)
                    }
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(TTColor.inkTertiary)
                        .padding(.horizontal, 9)
                        .alignmentGuide(.lastTextBaseline) { $0[VerticalAlignment.center] + 9 }
                    Text(verbatim: row.arrival)
                        .font(TTFont.widgetRowArrival)
                        .tracking(-0.4)
                        .monospacedDigit()
                        .foregroundStyle(TTColor.inkSecondary)
                    Spacer(minLength: 0)
                }
                .lineLimit(1)
                .frame(height: 34)
            }
        }
    }

    /// "in 11 min" in the accent on the first row, the rest ink secondary: "in 41 min", "Today", "Mon". On a tinted Home
    /// Screen iOS tints only a marked group of two or more drawn pieces, so "in" and the minutes stay apart and "now" is
    /// drawn twice, one over the other (TT-239, #232: a lone marked text stayed white).
    @ViewBuilder
    private func when(_ row: DeparturesContent.Row) -> some View {
        let color = row.isLead ? TTColor.accent : TTColor.inkSecondary
        switch row.when {
        case .now:
            WidgetNowText(isTinted: !look.isFullColor)
                .foregroundStyle(color)
                .widgetAccentable(row.isLead)
        case .countdown(let minutes):
            HStack(spacing: 4) {
                Text("widget.in")
                Text(verbatim: minutes)
            }
            .foregroundStyle(color)
            .widgetAccentable(row.isLead)
        case .day(let day):
            Text(verbatim: day)
                .foregroundStyle(TTColor.inkSecondary)
        }
    }

    /// "Next 8:06 8:28 8:58": the trains after the row's on its day, each opening its Trip details.
    private func next(_ later: [DeparturesContent.Later]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("widget.next")
                .font(TTFont.footnote)
                .foregroundStyle(TTColor.inkSecondary)
            ForEach(later) { later in
                Link(destination: later.link) {
                    Text(verbatim: later.time)
                        .font(TTFont.widgetFooterTime)
                        .monospacedDigit()
                        .foregroundStyle(TTColor.ink)
                }
            }
        }
        .tracking(-0.1)
        .lineLimit(1)
        .fixedSize()
    }

    // MARK: Message

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

/// "now", drawn twice one over the other on a tinted Home Screen, where iOS tints a marked group only when it has two or
/// more drawn pieces (TT-239, #232); once in full colour, so the full-colour widgets draw as before.
struct WidgetNowText: View {
    let isTinted: Bool

    var body: some View {
        if isTinted {
            ZStack {
                Text("widget.now")
                Text("widget.now")
            }
        } else {
            Text("widget.now")
        }
    }
}
