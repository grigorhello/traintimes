import SwiftUI

/// Trip status from the closed set (D12). Colour + word + icon, never colour alone.
enum TripStatus: Hashable, Sendable {
    case onTime
    case delayed(minutes: Int)
    case cancelled
    case stopSkipped
    case scheduled
    /// `time` is already formatted by the one time formatter.
    case lastReported(time: String)
    case offline
    /// Trip details after the train has left (TT-163): a display state of the sheet, not a domain status (D12).
    case departed
    /// The train stands at the rider's station with its platform posted (TT-233, D114, `BoardingRule`): a display state of
    /// the timeline card, like `departed`. Its dot pings on `StatusLine`.
    case boarding

    var text: String {
        switch self {
        case .onTime: String(localized: "status.on_time")
        case .delayed(let minutes): String(format: String(localized: "status.delayed"), TimeFormatter.duration(minutes: minutes))
        case .cancelled: String(localized: "status.cancelled")
        case .stopSkipped: String(localized: "status.stop_skipped")
        case .scheduled: String(localized: "status.scheduled")
        case .lastReported(let time): String(format: String(localized: "status.last_reported"), time)
        case .offline: String(localized: "status.offline")
        case .departed: String(localized: "trip.departed")
        case .boarding: String(localized: "status.boarding")
        }
    }

    var symbol: String {
        switch self {
        case .onTime: "checkmark.circle.fill"
        case .delayed: "clock.badge.exclamationmark"
        case .cancelled, .stopSkipped: "xmark.circle.fill"
        case .scheduled, .lastReported: "clock"
        case .offline: "wifi.slash"
        case .departed: "checkmark.circle"
        case .boarding: "figure.walk.circle.fill"
        }
    }

    var ink: Color {
        switch self {
        case .onTime: TTColor.ontimeInk
        case .delayed: TTColor.delayInk
        case .cancelled, .stopSkipped: TTColor.cancelInk
        case .scheduled, .lastReported, .offline: TTColor.scheduledInk
        case .departed: TTColor.inkSecondary
        case .boarding: TTColor.accent
        }
    }

    var fill: Color {
        switch self {
        case .onTime: TTColor.ontimeFill
        case .delayed: TTColor.delayFill
        case .cancelled, .stopSkipped: TTColor.cancelFill
        case .scheduled, .lastReported, .offline, .departed: TTColor.scheduledFill
        case .boarding: TTColor.accentSoft
        }
    }

    /// Live information (TT-157, D50): a filled dot on the card's status line. Scheduled, stale and offline get a ring.
    var isLive: Bool {
        switch self {
        case .onTime, .delayed, .cancelled, .stopSkipped, .departed, .boarding: true
        case .scheduled, .lastReported, .offline: false
        }
    }
}

/// The pill badge, in the component gallery only since TT-163 (the timeline card and Trip details use `StatusLine`, D50).
struct StatusBadge: View {
    let status: TripStatus

    var body: some View {
        Label {
            Text(status.text).monospacedDigit()
        } icon: {
            Image(systemName: status.symbol)
        }
        .labelStyle(BadgeLabelStyle())
        .font(TTFont.badge)
        .foregroundStyle(status.ink)
        // A badge never wraps its text; the row around it wraps instead.
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, TTSpace.s2)
        .padding(.vertical, TTSpace.s1)
        .background(status.fill, in: Capsule())
    }
}

/// The timeline card's status (TT-157, D50): a 10 pt dot and the word, 15 pt semibold, in the status colour. Filled for
/// live information, a ring for Scheduled, Last reported and Offline. No pill, no icon. Boarding's dot pings (TT-233).
struct StatusLine: View {
    let status: TripStatus

    private static let dot: CGFloat = 10
    private static let ringWidth: CGFloat = 2
    private static let minimumScale: CGFloat = 0.85

    var body: some View {
        HStack(spacing: TTSpace.s2) {
            Group {
                if status.isLive {
                    Circle().fill(status.ink)
                } else {
                    Circle().strokeBorder(status.ink, lineWidth: Self.ringWidth)
                }
            }
            .frame(width: Self.dot, height: Self.dot)
            .background {
                if status == .boarding { BoardingPing(colour: status.ink, dot: Self.dot) }
            }
            .accessibilityHidden(true)
            Text(status.text)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(Self.minimumScale)
        }
        .font(TTFont.badgeLarge)
        .foregroundStyle(status.ink)
    }
}

/// The status row of the train you ride on Schedule (TT-256, D130, Card states board 9, option A): the train glyph and
/// "You’re on board" in the accent, in the status line's font, where the dot and status were. About 134 pt, inside the
/// 137 pt the row leaves beside "Arrival 12:58 PM"; it shrinks a little rather than truncate.
struct OnBoardMark: View {
    private static let glyph: CGFloat = 16
    private static let minimumScale: CGFloat = 0.85

    var body: some View {
        HStack(spacing: TTSpace.s1 + 2) {
            TrainGlyph()
                .fill(TTColor.accent, style: FillStyle(eoFill: true))
                .frame(width: Self.glyph, height: Self.glyph)
                .accessibilityHidden(true)
            Text("onboard.youreOnBoard")
                .lineLimit(1)
                .minimumScaleFactor(Self.minimumScale)
        }
        .font(TTFont.badgeLarge)
        .foregroundStyle(TTColor.accent)
    }
}

/// The Boarding dot's ping (TT-233, D114): a halo that grows from the dot to 7 pt out while it fades, every 1.6 s, drawn
/// from the clock so every Boarding dot on screen pings together and a redraw never restarts it. No halo with Reduce
/// Motion, or when Schedule's motion is off (`\.playsScheduleMotion`, the unit test host), so snapshots are still.
struct BoardingPing: View {
    @Environment(\.playsScheduleMotion) private var playsMotion
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let colour: Color
    /// The dot's diameter; the halo starts at its edge.
    let dot: CGFloat

    static let period = 1.6
    /// How far past the dot's edge the halo reaches.
    static let reach: CGFloat = 7
    /// The halo's strength as it starts.
    static let strength = 0.6

    var body: some View {
        if playsMotion, !reduceMotion {
            TimelineView(.animation) { context in
                let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.period) / Self.period
                let progress = UnitCurve.easeOut.value(at: phase)
                let size = dot + 2 * Self.reach * progress
                Circle()
                    .fill(colour)
                    .frame(width: size, height: size)
                    .opacity(Self.strength * (1 - progress))
                    // The halo grows past the dot's own box without moving the row.
                    .frame(width: dot, height: dot)
            }
            .allowsHitTesting(false)
        }
    }
}

/// Express on the timeline card (TT-157, D50): a 16 pt bolt in an 18 pt box, accent when the stopping-pattern rule (D35)
/// marks the train express, control-border with a slash when it does not, so every card keeps the same shape.
struct ExpressBolt: View {
    let isExpress: Bool

    private static let glyph: CGFloat = 16
    private static let box: CGFloat = 18

    var body: some View {
        Image(systemName: isExpress ? "bolt.fill" : "bolt.slash.fill")
            .font(.system(size: Self.glyph, weight: .semibold))
            .foregroundStyle(isExpress ? TTColor.accent : TTColor.controlBorder)
            .frame(width: Self.box, height: Self.box)
            .accessibilityLabel(Text("tag.express"))
            .accessibilityHidden(!isExpress)
    }
}

/// Minute pill on the timeline rail. `time` is formatted by the one time formatter.
struct TimePill: View {
    enum Style: Sendable { case next, later, slipped, cancelled }

    /// The fixed slot every pill takes on the rail, so times line up in the label column.
    static let railSize = CGSize(width: 40, height: 22)

    let time: String
    var style: Style = .later
    /// On the timeline the pill fills `railSize`; elsewhere it hugs its text.
    var isOnRail = false

    var body: some View {
        Text(time)
            // The slipped scheduled time is regular weight on the canvas (`.tl-pill.ghost`); the others are semibold.
            .font(style == .slipped ? TTFont.badge.weight(.regular) : TTFont.badge)
            .monospacedDigit()
            .strikethrough(style == .slipped || style == .cancelled)
            .foregroundStyle(ink)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, isOnRail ? 0 : 6)
            .padding(.vertical, isOnRail ? 0 : 2)
            .frame(width: isOnRail ? Self.railSize.width : nil, height: isOnRail ? Self.railSize.height : nil)
            .background(fill, in: Capsule())
    }

    private var ink: Color {
        switch style {
        case .next: TTColor.onAccent
        case .later: TTColor.accent
        case .slipped: TTColor.delayInk
        case .cancelled: TTColor.cancelInk
        }
    }

    private var fill: Color {
        switch style {
        case .next: TTColor.accent
        case .later: TTColor.accentSoft
        case .slipped: TTColor.delayFill
        case .cancelled: TTColor.cancelFill
        }
    }
}

private struct BadgeLabelStyle: LabelStyle {
    var spacing: CGFloat = TTSpace.s1

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: spacing) {
            configuration.icon
            configuration.title
        }
    }
}

#Preview("Badges") { BadgesGallery() }
#Preview("Badges dark") { BadgesGallery().preferredColorScheme(.dark) }
