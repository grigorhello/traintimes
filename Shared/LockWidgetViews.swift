import SwiftUI
import WidgetKit

// Next train's Lock Screen sizes (TT-184, D115; boards Widgets-Lock and the "Lock Screen" row of Widgets-States), in
// `Shared/` so the app's unit tests snapshot what the extension draws. iOS draws the Lock Screen in one tint: the primary
// and secondary styles only, no token colours and no line tile; the glyph, the bolt, the bell and the words carry the
// meaning. Every word comes from `LockRectangularContent`, `LockCircularContent` and `LockInlineContent`.
//
// The plate and the disc behind them are iOS's own (`AccessoryWidgetBackground`), passed in by the extension; the snapshot
// tests pass a stand-in. On the Always-On display (`isDimmed`) both go.

private enum LockWidgetSymbol {
    /// The train in the rectangular's first row and above the circular's number.
    static let glyph = Font.system(size: 11, weight: .semibold)
    /// The bell, and the bolt beside the time.
    static let mark = Font.system(size: 10, weight: .semibold)
    static let bolt = Font.system(size: 12, weight: .semibold)
    /// The train alone in the circular, with no time to write.
    static let alone = Font.system(size: 26, weight: .semibold)
}

/// A line with its time strong: primary and semibold in the secondary text.
private func lockLine(_ text: WidgetText) -> AttributedString {
    var result = AttributedString()
    for piece in text.pieces {
        var run = AttributedString(piece.text)
        run.font = (piece.isStrong ? TTFont.badge : TTFont.footnote).monospacedDigit()
        run.foregroundColor = piece.isStrong ? Color.primary : Color.secondary
        result += run
    }
    return result
}

// MARK: - Rectangular

/// Rectangular (160 × 72 pt on the boards): the route, the time with the bolt, and the countdown with the train after.
struct LockRectangularView<Plate: View>: View {
    let content: LockRectangularContent
    /// The Always-On display: no plate.
    var isDimmed = false
    @ViewBuilder var plate: () -> Plate

    var body: some View {
        rows
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(EdgeInsets(top: 8, leading: 10, bottom: 6, trailing: 10))
            .background {
                if !isDimmed {
                    plate().clipShape(RoundedRectangle(cornerRadius: TTRadius.lg, style: .continuous))
                }
            }
    }

    @ViewBuilder
    private var rows: some View {
        switch content.body {
        case .train(let train):
            VStack(alignment: .leading, spacing: 0) {
                header(train.header)
                time(train.time, isExpress: train.isExpress)
                note(train.note, hasBell: train.thenIsAlerted)
            }
        case .noTrains(let quiet):
            VStack(alignment: .leading, spacing: 0) {
                header(.route(from: quiet.from, to: quiet.to))
                Text(noTrains(quiet.when))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(height: 26)
                if let note = quiet.note {
                    self.note(note, hasBell: false)
                }
            }
        case .message(let message):
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: message.title)
                    .font(TTFont.widgetStrong)
                    .tracking(-0.2)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let detail = message.detail {
                    Text(verbatim: detail.plain)
                        .font(TTFont.footnote)
                        .tracking(-0.1)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    /// The train and "Oakville → Union", or the train, the bell and "Your train · Union".
    private func header(_ header: LockRectangularContent.Header) -> some View {
        HStack(spacing: 4) {
            Image(systemName: LockWidgetGlyph.train.symbol)
                .font(LockWidgetSymbol.glyph)
            switch header {
            case .route(let from, let to):
                Text(verbatim: "\(from) \u{2192} \(to)")
            case .yourTrain(let to):
                Image(systemName: LockWidgetGlyph.bell.symbol)
                    .font(LockWidgetSymbol.mark)
                Text(verbatim: "\(String(localized: "widget.your_train")) · \(to)")
            }
        }
        .font(TTFont.badge)
        .tracking(-0.1)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.65)
        .frame(height: 16)
        // A long name ("West Harbour → Niagara Falls") may run 6 pt into the right margin before it is cut.
        .padding(.trailing, -6)
    }

    /// "8:06 AM" and the bolt of an express, level with the middle of the digits.
    private func time(_ clock: WidgetClock, isExpress: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(verbatim: clock.digits)
                .font(TTFont.lockTime)
                .tracking(-0.5)
                .monospacedDigit()
                .contentTransition(.numericText())
                .fixedSize()
            if let period = clock.period {
                Text(verbatim: period)
                    .font(TTFont.lockPeriod)
                    .tracking(-0.2)
                    .fixedSize()
            }
            if isExpress {
                Image(systemName: "bolt.fill")
                    .font(LockWidgetSymbol.bolt)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 8 }
            }
        }
        .foregroundStyle(.primary)
        .lineLimit(1)
        .frame(height: 26)
    }

    /// "in 5 min · then 8:28" and the bell of an alerted train.
    private func note(_ text: WidgetText, hasBell: Bool) -> some View {
        HStack(spacing: 3) {
            Text(lockLine(text))
                .tracking(-0.1)
                .contentTransition(.numericText())
            if hasBell {
                Image(systemName: LockWidgetGlyph.bell.symbol)
                    .font(LockWidgetSymbol.mark)
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .frame(height: 16)
    }

    /// "No trains" at the time's size and "tonight" at AM's, one text so a narrow widget shrinks them together.
    private func noTrains(_ when: String) -> AttributedString {
        var title = AttributedString(String(localized: "widget.lock.no_trains"))
        title.font = TTFont.lockTime
        title.tracking = -0.5
        var tail = AttributedString(" \(when)")
        tail.font = TTFont.lockPeriod
        tail.tracking = -0.2
        var result = title + tail
        result.foregroundColor = Color.primary
        return result
    }
}

// MARK: - Circular

/// Circular (72 pt on the boards): the train or the bell, the minutes and "min", inside the ring.
struct LockCircularView<Disc: View>: View {
    let content: LockCircularContent
    /// The Always-On display: no disc.
    var isDimmed = false
    @ViewBuilder var disc: () -> Disc

    var body: some View {
        ZStack {
            if !isDimmed {
                disc().clipShape(Circle())
            }
            if let ring = content.ring {
                LockWidgetRing(left: ring)
            }
            centre
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var centre: some View {
        if let value = content.value {
            VStack(spacing: 0) {
                Image(systemName: content.glyph.symbol)
                    .font(LockWidgetSymbol.glyph)
                    .frame(height: 14)
                    .padding(.bottom, 1)
                // A clock time is wider than the ring's inside: it shrinks for width only (its own height, so the
                // 26 pt row does not shrink it too).
                Text(verbatim: value)
                    .font(TTFont.lockNumber)
                    .tracking(-0.6)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.numericText())
                    .frame(width: 48, height: 26)
                // The caption's row stays when there is none, so a clock time sits where the minutes do, across the
                // disc's widest part: a row lower its corners touched the ring. Down here the ring's inside is 29 pt
                // wide, so "11:47" under "now" (33 pt) shrinks to 26 pt (for width only, as above).
                Text(verbatim: content.caption ?? " ")
                    .font(TTFont.lockUnit)
                    .tracking(0.1)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 26, height: 13)
            }
            .foregroundStyle(.primary)
        } else {
            Image(systemName: content.glyph.symbol)
                .font(LockWidgetSymbol.alone)
                .foregroundStyle(.primary)
        }
    }
}

/// The circular's ring: a faint track and what is left of the 30 min, from the top, clockwise.
private struct LockWidgetRing: View {
    /// 1 is the whole ring, 0 none of it.
    let left: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.22), lineWidth: 5)
            Circle()
                .trim(from: 0, to: left)
                .stroke(Color.primary, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(5)
    }
}

// MARK: - Inline

/// Inline, beside the date: the glyph and one line, which loses "to Union" where there is no room. iOS sets the font.
struct LockInlineView: View {
    let content: LockInlineContent

    var body: some View {
        ViewThatFits(in: .horizontal) {
            label(content.text)
            if let short = content.short {
                label(short)
            }
        }
    }

    private func label(_ text: String) -> some View {
        Label {
            Text(verbatim: text)
        } icon: {
            Image(systemName: content.glyph.symbol)
        }
        .labelStyle(.titleAndIcon)
        .lineLimit(1)
    }
}
