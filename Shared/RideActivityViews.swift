import SwiftUI

// The On board Live Activity's views (TT-174, D67), after the canvas's Live-Lock, Live-Lock-Arriving and Live-Island
// boards. The widget extension draws them on the Lock Screen and in the Dynamic Island; they live here, beside the
// attributes, so the app's snapshot tests can draw them too. The boards draw the activity dark in both appearances (the
// island is always black), so these views keep their own palette rather than the app's tokens, which the extension does
// not have.

/// The activity's colours: mint on the dark card and in the black island, white on the arriving green; grey once stale.
struct RideActivityStyle {
    static let mint = Color(red: 110 / 255, green: 231 / 255, blue: 183 / 255)
    /// Brand green, #0C7B53: the arriving alert.
    static let alertGreen = Color(red: 12 / 255, green: 123 / 255, blue: 83 / 255)
    /// The Lock Screen card, #1C202A, at 78 % over the wallpaper.
    static let lockGround = Color(red: 28 / 255, green: 32 / 255, blue: 42 / 255).opacity(0.78)
    /// The train's disc on the Lock Screen card, which hides the bar under it.
    static let lockDisc = Color(red: 30 / 255, green: 35 / 255, blue: 46 / 255)

    let isAlert: Bool
    let isStale: Bool
    /// What the train's disc is filled with: the card, the island's black or the alert green.
    let surface: Color

    /// The Lock Screen card.
    static func lock(_ state: RideActivityAttributes.ContentState, isStale: Bool) -> RideActivityStyle {
        RideActivityStyle(isAlert: state.isAlert, isStale: isStale, surface: state.isAlert ? alertGreen : lockDisc)
    }

    /// The Dynamic Island, black; the arriving card in it is green.
    static func island(_ state: RideActivityAttributes.ContentState, isStale: Bool) -> RideActivityStyle {
        RideActivityStyle(isAlert: state.isAlert, isStale: isStale, surface: state.isAlert ? alertGreen : .black)
    }

    /// The countdown, the bar's done part, the train and the pin.
    var tint: Color { isStale ? .white.opacity(0.45) : isAlert ? .white : Self.mint }
    var secondary: Color { .white.opacity(isAlert ? 0.82 : 0.72) }
    var track: Color { .white.opacity(isAlert ? 0.35 : 0.22) }
    var stopDot: Color { .white.opacity(isAlert ? 0.4 : 0.45) }
    var tileEdge: Color { .white.opacity(isAlert ? 0.4 : 0.16) }
}

extension EnvironmentValues {
    /// Snapshot tests stop the countdown at this time, so it draws the same on every run; nil lets it run on the device.
    @Entry var rideActivityPausedAt: Date? = nil
}

// MARK: Pieces

/// The line's code on a tile in its colour (D49): 40 pt on the card, 22 pt in the compact island, 26 pt in the minimal one.
struct RideActivityTile: View {
    enum Size {
        case large, compact, minimal
    }

    let attributes: RideActivityAttributes
    let size: Size
    var edge: Color = .clear

    var body: some View {
        let metrics = metrics
        Text(verbatim: attributes.lineCode)
            .font(.system(size: metrics.font, weight: .bold))
            .tracking(metrics.tracking)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(.white)
            .frame(width: metrics.side, height: metrics.side)
            .background(Self.color(hex: attributes.lineColorHex), in: RoundedRectangle(cornerRadius: metrics.radius))
            .overlay(RoundedRectangle(cornerRadius: metrics.radius).strokeBorder(edge, lineWidth: 1))
    }

    private var metrics: (side: CGFloat, radius: CGFloat, font: CGFloat, tracking: CGFloat) {
        switch size {
        case .large: (40, 11, 15, 0.5)
        case .compact: (22, 6, 9, 0.3)
        case .minimal: (26, 7, 10, 0.3)
        }
    }

    /// "#8B1A31"; grey without one.
    static func color(hex: String?) -> Color {
        let digits = hex.map { $0.hasPrefix("#") ? String($0.dropFirst()) : $0 } ?? ""
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return .white.opacity(0.3) }
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

/// The countdown as timer text, which runs on the device with no updates, in a fixed width so the card does not shift as
/// the digits change; "Now" at a station and at your stop.
struct RideActivityCountdown: View {
    let state: RideActivityAttributes.ContentState
    let style: RideActivityStyle
    let fontSize: CGFloat
    /// Wide enough for "29:59".
    let width: CGFloat
    @Environment(\.rideActivityPausedAt) private var pausedAt

    var body: some View {
        Group {
            if let end = state.countdownEnd {
                let start = min(end, pausedAt ?? Date())
                Text(timerInterval: start...end, pauseTime: pausedAt, countsDown: true, showsHours: false)
            } else {
                Text(state.now)
            }
        }
        .font(.system(size: fontSize, weight: .semibold))
        .tracking(fontSize > 20 ? -0.6 : -0.2)
        .monospacedDigit()
        .lineLimit(1)
        .multilineTextAlignment(.trailing)
        .foregroundStyle(style.tint)
        .frame(width: width, alignment: .trailing)
    }
}

/// "Next stop · Port Credit" (the dot regular and grey) over "Clarkson 5:43 PM · 2 stops"; "Updated 5:31 PM" once stale.
struct RideActivityTitle: View {
    let state: RideActivityAttributes.ContentState
    let style: RideActivityStyle

    var body: some View {
        // One line each, shrunk to fit rather than cut off: the expanded island's centre is narrow for "Next stop · St.
        // Catharines".
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(style.isStale ? state.updated : state.detail)
                .font(.system(size: 13))
                .tracking(-0.1)
                .monospacedDigit()
                .foregroundStyle(style.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var title: AttributedString {
        var text = AttributedString(state.title)
        text.font = .system(size: 17, weight: .semibold)
        text.foregroundColor = .white
        text.tracking = -0.4
        if let dot = text.range(of: " · ") {
            text[dot].font = .system(size: 17, weight: .regular)
            text[dot].foregroundColor = style.secondary
        }
        return text
    }
}

/// The countdown with its time under it, on the card and in the expanded island's trailing corner.
struct RideActivityCountdownStack: View {
    let state: RideActivityAttributes.ContentState
    let style: RideActivityStyle

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            RideActivityCountdown(state: state, style: style, fontSize: 28, width: 76)
                .frame(height: 32)
            Text(state.time)
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(style.secondary)
                .lineLimit(1)
        }
    }
}

/// "Clarkson 5:43 PM" with the station white and semibold.
struct RideActivityArrival: View {
    let attributes: RideActivityAttributes
    let state: RideActivityAttributes.ContentState
    let style: RideActivityStyle
    var fontSize: CGFloat = 12

    var body: some View {
        Text(text)
            .tracking(-0.1)
            .monospacedDigit()
            .lineLimit(1)
    }

    private var text: AttributedString {
        var text = AttributedString(state.arrival)
        text.font = .system(size: fontSize)
        text.foregroundColor = style.secondary
        if let name = text.range(of: attributes.destinationName) {
            text[name].font = .system(size: fontSize, weight: .semibold)
            text[name].foregroundColor = .white
        }
        return text
    }
}

/// The stop bar: a dot for each stop (the origin's larger), your stop's pin at the end, mint behind the train; the train
/// glyph alone on a disc of the background's colour, moving with a 0.6 s ease on each update.
struct RideActivityBar: View {
    let stopCount: Int
    let position: Double
    let style: RideActivityStyle

    static let height: CGFloat = 20

    var body: some View {
        GeometryReader { geometry in
            let layout = Layout(width: geometry.size.width, stops: max(2, stopCount))
            let at = min(max(position, 0), Double(layout.stops - 1))
            let passed = Int(at.rounded(.down))
            let mid = Self.height / 2
            ZStack(alignment: .topLeading) {
                ForEach(0..<(layout.stops - 1), id: \.self) { index in
                    let fill: Double = index < passed ? 1 : index == passed ? at - Double(passed) : 0
                    ZStack(alignment: .leading) {
                        Capsule().fill(style.track)
                        Capsule().fill(style.tint).frame(width: layout.segment * CGFloat(fill))
                    }
                    .frame(width: layout.segment, height: 3)
                    .position(x: layout.segmentStart(index) + layout.segment / 2, y: mid)
                }
                ForEach(0..<(layout.stops - 1), id: \.self) { stop in
                    Circle()
                        .fill(stop <= passed ? style.tint : style.stopDot)
                        .frame(width: stop == 0 ? 9 : 7, height: stop == 0 ? 9 : 7)
                        .position(x: layout.center(of: stop), y: mid)
                }
                RideActivityPin()
                    .fill(style.tint, style: FillStyle(eoFill: true))
                    .frame(width: 16, height: 16)
                    .position(x: layout.center(of: layout.stops - 1), y: mid)
                ZStack {
                    Circle().fill(style.surface).frame(width: 22, height: 22)
                    TrainGlyph()
                        .fill(style.tint, style: FillStyle(eoFill: true))
                        .frame(width: 24, height: 24)
                }
                .position(x: layout.x(at), y: mid)
                .animation(.easeInOut(duration: 0.6), value: position)
            }
        }
        .frame(height: Self.height)
    }

    /// The board's flex row: the origin's 9 pt dot and 1 pt margins, 7 pt dots with 1 pt margins, the 16 pt pin after a
    /// 2 pt margin, and equal segments between.
    struct Layout {
        let width: CGFloat
        let stops: Int

        var segment: CGFloat {
            max(0, (width - 11 - 9 * CGFloat(stops - 2) - 18) / CGFloat(stops - 1))
        }

        /// Where the segment from stop `index` to the next one starts.
        func segmentStart(_ index: Int) -> CGFloat {
            11 + CGFloat(index) * (segment + 9)
        }

        func center(of stop: Int) -> CGFloat {
            if stop <= 0 { return 5.5 }
            if stop >= stops - 1 { return width - 8 }
            return segmentStart(stop) - 4.5
        }

        /// The train at `position` stops from the origin: on a stop's dot, else along the segment after it.
        func x(_ position: Double) -> CGFloat {
            let index = Int(position.rounded(.down))
            let fraction = position - Double(index)
            guard index < stops - 1, fraction > 0.001 else { return center(of: min(index, stops - 1)) }
            return segmentStart(index) + segment * fraction
        }
    }
}

/// Your stop's pin at the end of the bar, with its hole, in a 24 unit box.
struct RideActivityPin: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale)
        }
        var path = Path()
        path.move(to: point(12, 22.5))
        path.addCurve(to: point(19.5, 9.8), control1: point(12, 22.5), control2: point(19.5, 15.9))
        // Over the top: clockwise in the y-up sense SwiftUI's flag uses.
        path.addArc(
            center: point(12, 9.8), radius: 7.5 * scale, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: true
        )
        path.addCurve(to: point(12, 22.5), control1: point(4.5, 15.9), control2: point(12, 22.5))
        path.closeSubpath()
        path.addEllipse(in: CGRect(origin: point(9.2, 7), size: CGSize(width: 5.6 * scale, height: 5.6 * scale)))
        return path
    }
}

// MARK: The presentations

/// The Lock Screen card (*Live-Lock*): the line, the next stop and your stop, the countdown, the bar, the two ends. Its
/// background is the activity's tint, the card colour or the arriving green. The arriving card in the expanded island is
/// this one too, on green, without the two ends: the expanded island is at most 160 pt tall, the camera's row included.
struct RideActivityCard: View {
    let attributes: RideActivityAttributes
    let state: RideActivityAttributes.ContentState
    let style: RideActivityStyle
    var showsEnds = true

    var body: some View {
        VStack(alignment: .leading, spacing: showsEnds ? 12 : 10) {
            HStack(spacing: 12) {
                RideActivityTile(attributes: attributes, size: .large, edge: style.tileEdge)
                RideActivityTitle(state: state, style: style)
                Spacer(minLength: 0)
                RideActivityCountdownStack(state: state, style: style)
            }
            RideActivityBar(stopCount: attributes.stopCount, position: state.position, style: style)
            if showsEnds {
                ends
            }
        }
    }

    private var ends: some View {
        HStack {
            Text(state.departure)
                .font(.system(size: 12))
                .tracking(-0.1)
                .monospacedDigit()
                .foregroundStyle(style.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            RideActivityArrival(attributes: attributes, state: state, style: style)
        }
        .padding(.top, -4)
    }
}

/// The Lock Screen presentation, with the card's padding.
struct RideActivityLockView: View {
    let attributes: RideActivityAttributes
    let state: RideActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        RideActivityCard(attributes: attributes, state: state, style: .lock(state, isStale: isStale))
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
    }

    /// The card's colour behind it: the activity's background tint.
    static func background(_ state: RideActivityAttributes.ContentState) -> Color {
        state.isAlert ? RideActivityStyle.alertGreen : RideActivityStyle.lockGround
    }
}

/// The expanded island's bottom: the bar, your stop with its time, and End ride (a link, which works only in the expanded
/// island; Done at your stop). Kept short: the expanded island is at most 160 pt tall.
struct RideActivityExpandedBottom: View {
    let attributes: RideActivityAttributes
    let state: RideActivityAttributes.ContentState
    let style: RideActivityStyle

    var body: some View {
        VStack(spacing: 6) {
            RideActivityBar(stopCount: attributes.stopCount, position: state.position, style: style)
            HStack(spacing: 12) {
                RideActivityArrival(attributes: attributes, state: state, style: style, fontSize: 13)
                Spacer(minLength: 0)
                Link(destination: RideActivityLink.end.url) {
                    Text(state.button)
                        .font(.system(size: 14, weight: .semibold))
                        .tracking(-0.2)
                        .lineLimit(1)
                        .foregroundStyle(style.tint)
                        .padding(.horizontal, 14)
                        .frame(height: 26)
                        // Circular ends: a continuous capsule's outline shows a notch at each end on iOS 26.
                        .background(Capsule(style: .circular).strokeBorder(style.tint, lineWidth: 1.5))
                }
                // iOS masks the island's content inside its rounded corner: 4 pt in and up keeps the outline whole.
                .padding(.trailing, 4)
            }
            .padding(.bottom, 4)
        }
    }
}

/// The arriving alert in the expanded island: the card, without its two ends, on brand green inset in the island, whose
/// own background stays black (Apple does not let an activity colour it). About 96 pt, under the camera's row.
struct RideActivityExpandedAlert: View {
    let attributes: RideActivityAttributes
    let state: RideActivityAttributes.ContentState
    let style: RideActivityStyle

    var body: some View {
        RideActivityCard(attributes: attributes, state: state, style: style, showsEnds: false)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(RideActivityStyle.alertGreen, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

/// The compact island's trailing side, about 52 pt wide on the iPhone 17 Pro: the countdown or "Now", in white on a green
/// capsule while arriving ("Arriving · Clarkson", the board's words, does not fit beside the camera).
struct RideActivityCompactTrailing: View {
    let state: RideActivityAttributes.ContentState
    let style: RideActivityStyle

    var body: some View {
        if state.isAlert {
            RideActivityCountdown(state: state, style: style, fontSize: 15, width: 36)
                .padding(.horizontal, 6)
                .frame(height: 24)
                .background(RideActivityStyle.alertGreen, in: Capsule())
        } else {
            RideActivityCountdown(state: state, style: style, fontSize: 15, width: 42)
        }
    }
}
