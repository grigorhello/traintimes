import SwiftUI

// The On board Live Activity's views (TT-174, D67; one card for every moment since TT-205, D93, after the Live view canvas's
// boards 3, 12, 13 and 15). The widget extension draws them on the Lock Screen and in the Dynamic Island; they live here,
// beside the attributes, so the app's snapshot tests can draw them too. The activity is dark in both appearances (the
// island is always black), so these views keep their own palette rather than the app's tokens, which the extension does
// not have.

/// The activity's colours: white for the number, mint for boarding and from "is next" on, white on the green card; amber for
/// a late train's clock time; grey once stale.
struct RideActivityStyle {
    static let mint = Color(red: 110 / 255, green: 231 / 255, blue: 183 / 255)
    /// The dark delay ink, #FDE68A: a late train's clock time and its delay.
    static let amber = Color(red: 253 / 255, green: 230 / 255, blue: 138 / 255)
    /// Brand green, #0C7B53: the card arriving and at your stop.
    static let alertGreen = Color(red: 12 / 255, green: 123 / 255, blue: 83 / 255)
    /// The Lock Screen card, #1C202A, at 78 % over the wallpaper.
    static let lockGround = Color(red: 28 / 255, green: 32 / 255, blue: 42 / 255).opacity(0.78)
    /// The train's disc on the Lock Screen card, which hides the stop line under it.
    static let lockDisc = Color(red: 30 / 255, green: 35 / 255, blue: 46 / 255)

    /// The platform pill (TT-199): the number in white on a white tint, the dash in grey on a grey one.
    static let platform = PlatformBadge.Palette(
        numberInk: .white, numberFill: .white.opacity(0.16), dashInk: .white.opacity(0.62), dashFill: .white.opacity(0.16)
    )

    /// The card is brand green (on the Lock Screen, arriving and at your stop); the island stays black and its text goes
    /// mint instead.
    let isGreen: Bool
    let isStale: Bool
    /// The number turns mint: boarding, and from "is next" on.
    let isClose: Bool
    /// A late train: the clock time and the arrival in amber.
    let isLate: Bool
    /// What the train's disc is filled with: the card's colour, the island's black or the green.
    let surface: Color

    /// The Lock Screen card.
    static func lock(_ state: RideActivityAttributes.ContentState, isStale: Bool) -> RideActivityStyle {
        RideActivityStyle(
            isGreen: state.isGreen, isStale: isStale, isClose: state.isClose, isLate: state.late,
            surface: state.isGreen ? alertGreen : lockDisc
        )
    }

    /// The Dynamic Island, black in every moment (iOS draws it so).
    static func island(_ state: RideActivityAttributes.ContentState, isStale: Bool) -> RideActivityStyle {
        RideActivityStyle(isGreen: false, isStale: isStale, isClose: state.isClose, isLate: state.late, surface: .black)
    }

    private var grey: Color { .white.opacity(0.45) }

    /// The big number: white, mint when close (white on the green card).
    var number: Color { isStale ? grey : isGreen ? .white : isClose ? Self.mint : .white }
    /// The one line's words: grey on the dark card, mint in the island once close, light on green.
    var line: Color { isGreen ? .white.opacity(0.86) : isClose && !isStale ? Self.mint : .white.opacity(0.72) }
    /// The clock time in the line before departure: white semibold, amber when late.
    var time: Color { isStale ? grey : isLate ? Self.amber : .white }
    /// The label at the right, "Platform", "Arrives".
    var label: Color { .white.opacity(isGreen ? 0.82 : 0.72) }
    /// The value under it, "5:43 PM": white, amber when late.
    var value: Color { isStale ? grey : isLate ? Self.amber : .white }
    /// The stop line's done part, the train and the pin.
    var tint: Color { isStale ? grey : isGreen ? .white : Self.mint }
    var track: Color { .white.opacity(isGreen ? 0.35 : 0.22) }
    var stopDot: Color { .white.opacity(isGreen ? 0.4 : 0.45) }
    var tileEdge: Color { .white.opacity(isGreen ? 0.4 : 0.16) }
}

extension EnvironmentValues {
    /// Snapshot tests stop the countdown at this time, so it draws the same on every run; nil lets it run on the device.
    @Entry var rideActivityPausedAt: Date? = nil
}

// MARK: Pieces

/// The line's code on a tile in its colour (D49): 26 pt on the card and in the minimal island, 22 pt in the compact one.
struct RideActivityTile: View {
    enum Size {
        case card, compact, minimal
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
        case .card: (26, 7, 11, 0.3)
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

/// The big number: whole minutes, "15 min" (TT-219, D97: no seconds), text the app and the alert server update when the
/// minute changes, since iOS has no live "15 min" format; "Now" at your stop. A push from an older alert server, with no
/// minutes, still shows timer text running to `countdownEnd` ("11:59"), in a fixed width so what stands beside it does not
/// shift as the digits change.
struct RideActivityCountdown: View {
    let state: RideActivityAttributes.ContentState
    let color: Color
    let fontSize: CGFloat
    /// The timer's width, wide enough for "29:59": a narrower frame cuts "12:00" to "12:…".
    let width: CGFloat
    /// The minutes' width: nil sizes them to their words (the card), a number fits them in it (the compact island).
    var minutesWidth: CGFloat? = nil
    var alignment: Alignment = .leading
    @Environment(\.rideActivityPausedAt) private var pausedAt

    var body: some View {
        if let minutes = state.minutes {
            Text(minutes)
                .modifier(Styled(countdown: self))
                .minimumScaleFactor(0.6)
                .frame(width: minutesWidth, alignment: alignment)
        } else {
            Group {
                if let end = state.countdownEnd {
                    let start = min(end, pausedAt ?? Date())
                    Text(timerInterval: start...end, pauseTime: pausedAt, countsDown: true, showsHours: false)
                } else {
                    Text(state.now)
                }
            }
            .modifier(Styled(countdown: self))
            .frame(width: width, alignment: alignment)
        }
    }

    private struct Styled: ViewModifier {
        let countdown: RideActivityCountdown

        func body(content: Content) -> some View {
            content
                .font(.system(size: countdown.fontSize, weight: countdown.fontSize > 20 ? .bold : .semibold))
                .tracking(countdown.fontSize > 20 ? -1 : -0.2)
                .monospacedDigit()
                .lineLimit(1)
                .multilineTextAlignment(countdown.alignment == .leading ? .leading : .trailing)
                .foregroundStyle(countdown.color)
        }
    }
}

/// The stop line, no words (kept on the ride cards: Grigor asked for it back, TT-205): a dot for each stop (the origin's
/// larger), your stop's pin at the end, mint behind the train; the train glyph alone on a disc of the background's colour,
/// moving with a 0.6 s ease on each update.
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

// MARK: The card

extension RideActivityAttributes.ContentState {
    /// "5:13 PM" at the start of "5:13 PM departs in", "7:13" or "07:13" in 24-hour format: set in semibold.
    static func leadingTime(_ text: String) -> String? {
        let words = text.split(separator: " ")
        guard let first = words.first, first.contains(":") else { return nil }
        if words.count > 1, words[1] == "AM" || words[1] == "PM" { return "\(first) \(words[1])" }
        return String(first)
    }
}

/// The one card (TT-205, D93) on the Lock Screen and in the expanded island: the line's tile and the one line with the
/// label at the right; the number at 40 pt with the value under the label ("Platform" over the pill before departure,
/// "Arrives" over "5:43 PM" during the ride); during the ride the stop line under both. Arriving and at your stop the right
/// side is empty. Sizes 40, 26 and 15 pt; under 160 pt tall with the Lock Screen's padding.
struct RideActivityCard: View {
    let attributes: RideActivityAttributes
    let state: RideActivityAttributes.ContentState
    let style: RideActivityStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                RideActivityTile(attributes: attributes, size: .card, edge: style.tileEdge)
                Text(line)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                if !state.label.isEmpty {
                    Text(state.label)
                        .font(.system(size: 15))
                        .foregroundStyle(style.label)
                        .lineLimit(1)
                }
            }
            HStack(alignment: .center, spacing: 8) {
                if state.phase != .departed {
                    RideActivityCountdown(state: state, color: style.number, fontSize: 40, width: 118)
                    if let delay = state.delay, !style.isStale {
                        Text(delay)
                            .font(.system(size: 15, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(RideActivityStyle.amber)
                            .lineLimit(1)
                            .layoutPriority(-1)
                    }
                }
                Spacer(minLength: 0)
                trailing
            }
            .frame(height: 44)
            if !state.isDeparture {
                RideActivityBar(stopCount: attributes.stopCount, position: state.position, style: style)
                    .padding(.top, 4)
            }
        }
    }

    /// The pill before departure (the number, or the dash while it is not posted: still, since an activity does not
    /// animate); the arrival during the ride.
    @ViewBuilder private var trailing: some View {
        if state.isDeparture {
            PlatformBadge(number: state.platformNumber, size: 16, palette: RideActivityStyle.platform)
        } else if let value = state.value {
            Text(value)
                .font(.system(size: 26, weight: .bold))
                .tracking(-0.6)
                .monospacedDigit()
                .foregroundStyle(style.value)
                .lineLimit(1)
                .fixedSize()
        }
    }

    /// The line at 15 pt; before departure its clock time white and semibold (amber when late); "Updated 5:31 PM" once
    /// stale.
    private var line: AttributedString {
        var text = AttributedString(style.isStale ? state.updated : state.title)
        text.font = .system(size: 15, weight: .medium)
        text.foregroundColor = style.line
        text.tracking = -0.2
        if !style.isStale, state.isDeparture, let time = RideActivityAttributes.ContentState.leadingTime(state.title),
           let range = text.range(of: time) {
            text[range].font = .system(size: 15, weight: .semibold)
            text[range].foregroundColor = style.time
        }
        return text
    }
}

/// The Lock Screen presentation, with the card's padding; its background is the card colour, or brand green arriving and
/// at your stop.
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
        state.isGreen ? RideActivityStyle.alertGreen : RideActivityStyle.lockGround
    }
}

/// The expanded island: the same card under the camera, black in every moment (the text goes mint once close). Kept short:
/// the expanded island is at most 160 pt tall, the camera's row included.
struct RideActivityExpanded: View {
    let attributes: RideActivityAttributes
    let state: RideActivityAttributes.ContentState
    let style: RideActivityStyle

    var body: some View {
        RideActivityCard(attributes: attributes, state: state, style: style)
            .padding(.horizontal, 6)
            .padding(.bottom, 4)
    }
}

/// The compact island's trailing side, about 52 pt wide on the iPhone 17 Pro: the minutes to the train, then to your stop,
/// white, mint once close; nothing once the train has left before a ride.
struct RideActivityCompactTrailing: View {
    let state: RideActivityAttributes.ContentState
    let style: RideActivityStyle

    var body: some View {
        if state.phase != .departed {
            RideActivityCountdown(state: state, color: style.number, fontSize: 15, width: 48, minutesWidth: 48, alignment: .trailing)
        }
    }
}
