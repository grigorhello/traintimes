import SwiftUI

/// Trip details in ride mode (TT-204, D87, *Live-Ride-Lean*): the hero card with the minutes to your stop, and the stop
/// list with the train riding its rail. The two rise into place when the sheet opens on a ride.
struct RideContent: View {
    let ride: RideDetails
    /// False when the ride takes the departure card's place (TT-177, D69): the rows are there in the same update, with
    /// no rise, so the sheet never shows empty between the two.
    var risesIn = true
    /// The arrival wish's analytics and Tick (TT-223); nil in previews.
    var wishes: ArrivalWishes?
    /// The ride screen's Tick and Tap and its watch time (TT-224), for `engine`'s ride; nil in previews and snapshots.
    var screen: RideScreen?
    var engine: RideEngine?

    @Environment(\.playsRideMotion) private var playsMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var hasRisen = false

    /// What the screen's feels follow: a stop passing, your stop becoming next.
    private struct Moment: Equatable {
        let passed: Int
        let yoursIsNext: Bool
        let isComplete: Bool
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TTSpace.s3) {
            RideHero(ride: ride, wishes: wishes)
                .modifier(RideRise(order: 0, hasRisen: settled))
            RideStopList(ride: ride)
                .modifier(RideRise(order: 1, hasRisen: settled))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            hasRisen = true
            screen?.scene(isActive: scenePhase == .active)
            screen?.opened(engine)
            show(moment)
        }
        .onDisappear { screen?.closed() }
        .onChange(of: scenePhase) { _, phase in screen?.scene(isActive: phase == .active) }
        .onChange(of: moment) { _, new in show(new) }
    }

    private var moment: Moment {
        Moment(passed: ride.passed, yoursIsNext: ride.yoursIsNext, isComplete: ride.isComplete)
    }

    private func show(_ moment: Moment) {
        screen?.show(passed: moment.passed, yoursIsNext: moment.yoursIsNext, isComplete: moment.isComplete)
    }

    /// Snapshots draw the rows in place.
    private var settled: Bool { hasRisen || !playsMotion || !risesIn }
}

/// A row of the ride rising into place: 16 pt up and 0.97 to 1, on `RideMotion.rise` after its stagger; a fade with Reduce
/// Motion.
private struct RideRise: ViewModifier {
    let order: Int
    let hasRisen: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let moves = !reduceMotion
        content
            .opacity(hasRisen ? 1 : 0)
            .offset(y: hasRisen || !moves ? 0 : 16)
            .scaleEffect(hasRisen || !moves ? 1 : 0.97)
            .animation(
                (moves ? RideMotion.rise : TTMotion.fade).delay(RideMotion.riseDelay(order: order)),
                value: hasRisen
            )
    }
}

// MARK: Hero

/// The hero card: a 26 pt kicker naming your stop over the 64 pt minutes to it, and "5 min late" under them when late. Ink
/// until your stop is next, then the accent; arriving and at your stop tint the card and press it in. A new kicker rises
/// 10 pt as it fades in; the number changes in place.
struct RideHero: View {
    let ride: RideDetails
    var wishes: ArrivalWishes?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.playsRideMotion) private var playsMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: TTRadius.xl)
        let ink = ride.isClose ? TTColor.accent : TTColor.ink
        VStack(alignment: .leading, spacing: 0) {
            Text(ride.kicker)
                .font(TTFont.rideKicker)
                .tracking(-0.6)
                .foregroundStyle(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .id(ride.kicker)
                .transition(kickerRise)
            // The arrival wish rolls in where the number was, on its 68 pt line (TT-223, D103).
            ZStack(alignment: .leading) {
                if let wish = ride.wish {
                    ArrivalWishLine(wish: wish, wishes: wishes)
                        .transition(wishTransition(insertion: true))
                } else {
                    Text(ride.countdown)
                        .font(TTFont.rideMinutes)
                        .tracking(-2)
                        .monospacedDigit()
                        .foregroundStyle(ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.leading, -2)
                        .contentTransition(.numericText(countsDown: true))
                        .tracksInterest("ride.minutes")
                        .transition(wishTransition(insertion: false))
                }
            }
            .frame(height: 68)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(playsMotion && !reduceMotion ? RideMotion.wishIn : nil, value: ride.wish)
            if let late = ride.late {
                Text(late)
                    .font(TTFont.headline)
                    .tracking(-0.4)
                    .monospacedDigit()
                    .foregroundStyle(TTColor.delayInk)
                    .lineLimit(1)
                    .padding(.top, 2)
            }
        }
        .animation(playsMotion && !reduceMotion ? RideMotion.rise : nil, value: ride.kicker)
        .animation(.easeOut(duration: 0.15), value: ride.countdown)
        .animation(RideMotion.tint, value: ride.isClose)
        .padding(.top, TTSpace.s4)
        .padding(.bottom, TTSpace.s4)
        .padding(.horizontal, TTSpace.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ride.isTinted ? TTColor.accentSoft : TTColor.surface, in: shape)
        .overlay(shape.strokeBorder(edgeColour, lineWidth: ride.isTinted ? 1 : 0.5))
        .shadow(color: .black.opacity(colorScheme == .dark || ride.isTinted ? 0 : 0.06), radius: 1, x: 0, y: 1)
        .animation(RideMotion.tint, value: ride.isTinted)
        .overlay {
            // One sheen across the card when the train stops at your stop (TT-224, board 22).
            Color.clear
                .keyframeAnimator(initialValue: -1.0, trigger: sheenTrigger) { [peak = sheenPeak] content, x in
                    content.overlay {
                        GeometryReader { proxy in
                            let width = proxy.size.width * RideMotion.sheenWidth
                            LinearGradient(
                                colors: [.white.opacity(0), .white.opacity(peak), .white.opacity(0)],
                                startPoint: .leading, endPoint: .trailing
                            )
                            .frame(width: width)
                            .offset(x: -width + (proxy.size.width * 1.1 + width) * x)
                            .opacity(x > 0 && x < 1 ? 1 : 0)
                        }
                    }
                } keyframes: { _ in
                    KeyframeTrack(\.self) {
                        LinearKeyframe(0, duration: RideMotion.arrivalDelay)
                        CubicKeyframe(1, duration: RideMotion.sheenDuration)
                    }
                }
                .clipShape(shape)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .keyframeAnimator(initialValue: 1.0, trigger: pressTrigger) { content, scale in
            content.scaleEffect(scale, anchor: .bottomLeading)
        } keyframes: { [wait = pressWait] _ in
            KeyframeTrack(\.self) {
                // At your stop the press lands 120 ms after the check's pop (one overshoot at a time, D95).
                LinearKeyframe(1.0, duration: wait)
                LinearKeyframe(0.97, duration: 0.01)
                SpringKeyframe(
                    1.0, duration: 0.64,
                    spring: Spring(response: RideMotion.pressCurve.response, dampingRatio: RideMotion.pressCurve.damping)
                )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("trip.ride")
    }

    /// "Now" rolls up and out, the wish rolls in from below; a cross-fade with Reduce Motion, nothing in snapshots.
    private func wishTransition(insertion: Bool) -> AnyTransition {
        guard playsMotion else { return .identity }
        guard !reduceMotion else { return .opacity.animation(TTMotion.fade) }
        let roll = AnyTransition.modifier(
            active: WishRoll(offset: insertion ? RideMotion.wishTravel : -RideMotion.wishTravel, blur: RideMotion.wishBlur, opacity: 0),
            identity: WishRoll(offset: 0, blur: 0, opacity: 1)
        )
        return insertion
            ? .asymmetric(insertion: roll.animation(RideMotion.wishIn), removal: .opacity)
            : .asymmetric(insertion: .opacity, removal: roll.animation(RideMotion.wishOut))
    }

    /// Arriving and at your stop each press the card in once; not with Reduce Motion.
    private var pressTrigger: RideDetails.Moment? { ride.isTinted && !reduceMotion ? ride.moment : nil }

    /// The sheen plays once when the train reaches your stop; not in snapshots or with Reduce Motion.
    private var sheenTrigger: Bool { ride.isComplete && playsMotion && !reduceMotion }
    private var sheenPeak: Double { colorScheme == .dark ? 0.14 : 0.85 }
    /// At your stop the press waits for the check's pop.
    private var pressWait: Double { ride.isComplete && playsMotion ? RideMotion.arrivalPressDelay : 0.001 }

    /// The 1 pt accent edge of a tinted card, the 0.5 pt white edge of a dark one.
    private var edgeColour: Color {
        if ride.isTinted { return TTColor.accent.opacity(colorScheme == .dark ? 0.22 : 0.18) }
        return .white.opacity(colorScheme == .dark ? 0.08 : 0)
    }

    /// The new kicker rises 10 pt as it fades in.
    private var kickerRise: AnyTransition {
        reduceMotion ? .opacity : .asymmetric(insertion: .offset(y: 10).combined(with: .opacity), removal: .opacity)
    }
}

/// The arrival wish (TT-223, D103): 32 pt bold in the accent, one line, down to 0.8 for a long one. A tap pops it once with a
/// Tick and does nothing else. Its analytics: shown while the app is active, closed by the first way it leaves the screen
/// (Done and the sheet closing itself say so first; the app going away is `left_app`, anything else `dismissed`).
private struct ArrivalWishLine: View {
    let wish: ArrivalWish
    let wishes: ArrivalWishes?

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var taps = 0

    var body: some View {
        Text(verbatim: wish.text)
            .font(TTFont.rideWish)
            .tracking(-0.9)
            .foregroundStyle(TTColor.accent)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.leading, 2)
            .keyframeAnimator(initialValue: 1.0, trigger: taps) { content, scale in
                content.scaleEffect(scale, anchor: .leading)
            } keyframes: { _ in
                KeyframeTrack(\.self) {
                    LinearKeyframe(1.0, duration: 0.01)
                    LinearKeyframe(1.08, duration: 0.09)
                    SpringKeyframe(
                        1.0, duration: 0.5, spring: Spring(response: TTMotion.popCurve.response, dampingRatio: TTMotion.popCurve.damping)
                    )
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if !reduceMotion { taps += 1 }
                wishes?.tapped()
            }
            .accessibilityIdentifier("trip.ride.wish")
            .onAppear { if scenePhase == .active { wishes?.shown() } }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { wishes?.shown() }
                if phase == .background { wishes?.closed(.leftApp) }
            }
            .onDisappear { wishes?.closed(.dismissed) }
    }
}

/// A line rolling in or out of the hero's number line: moved, blurred and faded.
private struct WishRoll: ViewModifier {
    let offset: CGFloat
    let blur: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content.offset(y: offset).blur(radius: blur).opacity(opacity)
    }
}

// MARK: Stop list

/// The rail's geometry (TT-224): where each drawn row sits, and where the train is on it. Pure, so the train's place is
/// unit tested.
struct RideRail {
    let rows: [RideDetails.Row]
    let stopCount: Int

    static let row: CGFloat = 50
    static let fold: CGFloat = 26

    init(rows: [RideDetails.Row], stopCount: Int) {
        self.rows = rows
        self.stopCount = stopCount
        var top: CGFloat = 0
        tops = rows.map { row in
            defer { top += Self.height(row) }
            return top
        }
        totalHeight = top
    }

    /// The top of each drawn row.
    let tops: [CGFloat]
    let totalHeight: CGFloat

    static func height(_ drawn: RideDetails.Row) -> CGFloat {
        if case .fold = drawn { return fold }
        return row
    }

    /// The centre of the row that draws stop `index`; nil when it is folded away.
    func centre(ofStop index: Int) -> CGFloat? {
        guard let row = rows.firstIndex(where: { $0.stopIndex == index }) else { return nil }
        return tops[row] + Self.row / 2
    }

    /// The train's centre down the rail: on its stop's dot, or that far towards the next drawn stop, whatever lies folded
    /// between them (one stretch, crossed at the same pace). On the last stretch the stretch ends 24 pt short of your pin's
    /// centre, so the train keeps moving all the way and never covers the pin; nil (at your stop) is on the pin.
    func trainY(_ position: Double?) -> CGFloat {
        let last = max(0, stopCount - 1)
        guard let position else { return centre(ofStop: last) ?? Self.row / 2 }
        let index = min(max(Int(position.rounded(.down)), 0), last)
        let from = centre(ofStop: index) ?? Self.row / 2
        let next = (index + 1...max(index + 1, last)).first { centre(ofStop: $0) != nil } ?? index
        let to = centre(ofStop: min(next, last)) ?? from
        let fraction = CGFloat(position - Double(index))
        guard fraction > 0, next >= last else { return from + (to - from) * fraction }
        // The clock's fraction stops at 0.92 (`RideTimes.fraction`): that is where the shortened stretch ends.
        let end = max(from, to - RideMotion.pinClearance)
        return from + (end - from) * min(fraction / RideMotion.lastStretchEnd, 1)
    }

    /// The next drawn stop's centre ahead of the train, where the glint runs to.
    func nextY(_ position: Double?) -> CGFloat? {
        guard let position else { return nil }
        let last = max(0, stopCount - 1)
        let index = min(max(Int(position.rounded(.down)), 0), last)
        guard index < last else { return nil }
        return (index + 1...last).lazy.compactMap { centre(ofStop: $0) }.first
    }
}

/// The rail from where you got on to your stop (`RideDetails.rows`): passed stops before the last one, and stops between
/// the second one ahead and yours, fold into a short dotted row, so your stop stays on screen on a long trip. The rail turns
/// green behind the train, which stands on a stop's dot or travels between two by the clock, never on your stop's pin.
/// Your stop's row is always tinted; once it is next the rail to it is soft green and its pin answers the train's pulse;
/// at your stop the pin turns into a check that draws on. Passed stops have no time.
///
/// While the train moves one loop plays (TT-224, D106, board 19): a halo from the train, a glint along the rail ahead, the
/// next stop's dot answering. A stop passing pops its dot with one ring (board 20). Arriving at your stop, the train slides
/// into the pin, the check draws on with one ring (board 22). None of it in snapshots; no loop with Reduce Motion.
struct RideStopList: View {
    let ride: RideDetails

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.playsRideMotion) private var playsMotion
    /// The furthest the train was drawn on this stretch: it never goes back (`RideDetails.forward`).
    @State private var held: Double?

    static let row = RideRail.row
    static let fold = RideRail.fold
    private static let markerColumn: CGFloat = 20
    private static let rail: CGFloat = 2
    private static let marker: CGFloat = 30

    var body: some View {
        let position = RideDetails.forward(ride.trainPosition, from: held)
        let geometry = RideRail(rows: ride.rows, stopCount: ride.stops.count)
        let trainY = geometry.trainY(position)
        VStack(spacing: 0) {
            ForEach(Array(zip(ride.rows.indices, ride.rows)), id: \.1.id) { index, row in
                switch row {
                case .stop(let stop): stopRow(stop).transition(Self.rowTransition)
                case .fold: foldRow(top: geometry.tops[index], trainY: trainY, position: position).transition(Self.rowTransition)
                }
            }
        }
        .background(alignment: .topLeading) {
            // Your stop's tint lies under the rail, so the rail runs on into its pin.
            ZStack(alignment: .topLeading) {
                yourStopTint(geometry)
                rail(geometry, trainY: trainY, position: position)
                glint(geometry, trainY: trainY, position: position)
            }
        }
        .overlay(alignment: .topLeading) { train(trainY: trainY, position: position) }
        .contentShape(Rectangle())
        .tracksInterest("ride.stops")
        .padding(.horizontal, TTSpace.s4)
        .padding(.vertical, TTSpace.s2)
        .ttSheetCard()
        .animation(trainAnimation(position), value: position)
        .animation(reduceMotion ? nil : RideMotion.glide, value: ride.rows)
        .onChange(of: position) { _, new in held = new }
    }

    private var animates: Bool { playsMotion && !reduceMotion }

    /// A row folding away or unfolding fades quickly, so the rows sliding past it never show through it.
    private static let rowTransition = AnyTransition.opacity.animation(.easeOut(duration: 0.15))

    /// Creeping by the clock on a stretch, the glide onto a stop's dot, the slide into your pin after 450 ms.
    private func trainAnimation(_ position: Double?) -> Animation? {
        guard !reduceMotion else { return nil }
        guard let position else { return RideMotion.glide.delay(playsMotion ? RideMotion.arrivalDelay : 0) }
        guard let held, held.rounded(.down) == position.rounded(.down), position != position.rounded(.down) else {
            return RideMotion.glide
        }
        return RideMotion.creep
    }

    // MARK: Layers

    /// Grey from the first row's centre to the last one's, green as far as the train, soft green from the train to your pin
    /// once it is next.
    private func rail(_ geometry: RideRail, trainY: CGFloat, position: Double?) -> some View {
        let start = Self.row / 2
        let end = geometry.totalHeight - Self.row / 2
        let filled = position == nil ? end : trainY
        let x = Self.markerColumn / 2 - Self.rail / 2
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(TTColor.controlBorder.opacity(colorScheme == .dark ? 0.42 : 0.38))
                .frame(width: Self.rail, height: max(0, end - start))
            Rectangle()
                .fill(TTColor.accent)
                .frame(width: Self.rail, height: max(0, end - filled))
                .offset(y: filled - start)
                .opacity(ride.softensLastStretch ? RideMotion.softRailOpacity : 0)
                .animation(RideMotion.softRail, value: ride.softensLastStretch)
            Rectangle()
                .fill(TTColor.accent)
                .frame(width: Self.rail, height: max(0, filled - start))
        }
        .offset(x: x, y: start)
        .accessibilityHidden(true)
    }

    /// The glint running the rail ahead, from the train to the next drawn stop, once a loop while the train moves.
    @ViewBuilder
    private func glint(_ geometry: RideRail, trainY: CGFloat, position: Double?) -> some View {
        if animates, let loop = ride.loop, let nextY = geometry.nextY(position), nextY > trainY {
            let size = RideMotion.glintSize
            let top = trainY
            let length = nextY - top
            TimelineView(.animation) { context in
                let phase = RideMotion.loopPhase(at: context.date.timeIntervalSinceReferenceDate, loop: loop)
                let run = RideMotion.progress(phase, from: RideMotion.glintStart, to: RideMotion.glintEnd)
                let eased = run < 0.5 ? 2 * run * run : 1 - pow(-2 * run + 2, 2) / 2
                let shows = phase >= RideMotion.glintStart && phase < RideMotion.glintEnd
                LinearGradient(colors: [TTColor.accent.opacity(0), TTColor.accent, TTColor.accent], startPoint: .top, endPoint: .bottom)
                    .frame(width: size.width, height: size.height)
                    .clipShape(Capsule())
                    .offset(y: -size.height + (length + size.height) * eased)
                    .opacity(shows ? 1 : 0)
            }
            .frame(width: size.width, height: max(0, length), alignment: .top)
            .clipped()
            .offset(x: Self.markerColumn / 2 - size.width / 2, y: top)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// Your stop's row in accent soft, 10 pt wider than the rows on each side and 4 pt in from their edges.
    private func yourStopTint(_ geometry: RideRail) -> some View {
        RoundedRectangle(cornerRadius: TTRadius.md)
            .fill(TTColor.accentSoft)
            .frame(height: Self.row - 8)
            .padding(.horizontal, -10)
            .offset(y: geometry.totalHeight - Self.row + 4)
            .accessibilityHidden(true)
    }

    /// The train glyph on a surface disc, centred on the rail, with its halo while it moves; it slides into your pin and
    /// goes as the check draws on.
    private func train(trainY: CGFloat, position: Double?) -> some View {
        TrainMarker(loop: animates ? ride.loop : nil)
            .frame(width: Self.marker, height: Self.marker)
            .offset(x: Self.markerColumn / 2 - Self.marker / 2, y: trainY - Self.marker / 2)
            .opacity(position == nil ? 0 : 1)
            .animation(
                .easeOut(duration: 0.2).delay(position == nil && animates ? RideMotion.arrivalDelay + 0.1 : 0),
                value: position == nil
            )
            .accessibilityHidden(true)
    }

    // MARK: Rows

    private func stopRow(_ stop: RideDetails.Stop) -> some View {
        let isBold = stop.isNext || stop.isYours
        let colour: Color = stop.isYours && stop.isDone ? TTColor.accent : stop.isDone ? TTColor.inkTertiary : TTColor.ink
        let timeColour: Color = stop.isYours && stop.isDone ? TTColor.accent : stop.isLate ? TTColor.delayInk : TTColor.ink
        return HStack(spacing: TTSpace.s3) {
            marker(stop)
                .frame(width: Self.markerColumn, height: Self.row)
            Group {
                Text(verbatim: stop.name)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .foregroundStyle(colour)
                Spacer(minLength: TTSpace.s2)
                if let time = stop.time {
                    Text(time)
                        .monospacedDigit()
                        .foregroundStyle(timeColour)
                        // A passed stop's time goes at once, so it never slides over the next row's time as the list folds.
                        .transition(Self.rowTransition)
                }
            }
            // A passing stop's name and time fade to the passed style as its dot pops.
            .animation(animates && !stop.isYours ? RideMotion.passFade : nil, value: stop.isDone)
        }
        .font(isBold ? TTFont.headline : TTFont.body)
        .frame(height: Self.row)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("trip.ride.stop.\(stop.id)")
    }

    /// Stops left out: three dots on a surface gap in the rail, green when the train has passed them.
    private func foldRow(top: CGFloat, trainY: CGFloat, position: Double?) -> some View {
        let isPassed = position == nil || trainY > top + Self.fold / 2
        let dot = isPassed ? TTColor.accent : TTColor.controlBorder
        return HStack(spacing: 0) {
            VStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle().fill(dot).frame(width: 3, height: 3)
                }
            }
            .frame(width: Self.markerColumn, height: Self.fold)
            .background(TTColor.surface)
            Spacer(minLength: 0)
        }
        .frame(height: Self.fold)
        .accessibilityHidden(true)
    }

    @ViewBuilder private func marker(_ stop: RideDetails.Stop) -> some View {
        if stop.isYours {
            YourStopMarker(
                isComplete: ride.isComplete,
                answerLoop: animates && ride.softensLastStretch ? ride.loop : nil
            )
        } else {
            StopDot(stop: stop, answerLoop: animates && stop.isNext ? ride.loop : nil)
        }
    }
}

/// A stop's dot: ink and 10 pt when next, accent when passed, 12 pt where you got on. When the train lands on it, 320 ms
/// later it pops with one ring; while the train moves to it, it answers the pulse.
private struct StopDot: View {
    let stop: RideDetails.Stop
    /// The loop's length while this is the stop the train moves to.
    let answerLoop: Double?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.playsRideMotion) private var playsMotion

    private struct Pop {
        var dot: CGFloat = 1
        var ring: CGFloat = 1
        var ringOpacity: Double = 0
    }

    var body: some View {
        let size: CGFloat = stop.isFirst ? 12 : stop.isNext ? 10 : 8
        let pops = playsMotion && !reduceMotion
        TimelineView(.animation(minimumInterval: nil, paused: answerLoop == nil)) { context in
            Circle()
                .fill(stop.isNext ? TTColor.ink : stop.isDone ? TTColor.accent : TTColor.controlBorder)
                .frame(width: size, height: size)
                .animation(pops ? .easeOut(duration: 0.2).delay(RideMotion.passDelay) : nil, value: stop.isDone)
                .padding(2)
                .background(TTColor.surface, in: Circle())
                .scaleEffect(answer(at: context.date))
        }
        .keyframeAnimator(initialValue: Pop(), trigger: pops && stop.isDone) { content, pop in
            content
                .scaleEffect(pop.dot)
                .background {
                    Circle()
                        .strokeBorder(TTColor.accent, lineWidth: 1.5)
                        .frame(width: 8, height: 8)
                        .scaleEffect(pop.ring)
                        .opacity(pop.ringOpacity)
                }
        } keyframes: { _ in
            KeyframeTrack(\.dot) {
                LinearKeyframe(1, duration: RideMotion.passDelay)
                CubicKeyframe(RideMotion.popScale, duration: RideMotion.popDuration * 0.45)
                CubicKeyframe(1, duration: RideMotion.popDuration * 0.55)
            }
            KeyframeTrack(\.ring) {
                LinearKeyframe(1, duration: RideMotion.passDelay)
                LinearKeyframe(RideMotion.passRingScale, duration: RideMotion.passRingDuration, timingCurve: .easeOut)
            }
            KeyframeTrack(\.ringOpacity) {
                LinearKeyframe(0, duration: RideMotion.passDelay)
                LinearKeyframe(RideMotion.passRingOpacity, duration: 0.01)
                LinearKeyframe(0, duration: RideMotion.passRingDuration, timingCurve: .easeOut)
            }
        }
    }

    /// 1 until 57 % of the loop, 1.5 at 66 %, back to 1 at 84 %.
    private func answer(at date: Date) -> CGFloat {
        guard let answerLoop else { return 1 }
        let phase = RideMotion.loopPhase(at: date.timeIntervalSinceReferenceDate, loop: answerLoop)
        let up = RideMotion.progress(phase, from: RideMotion.answerStart, to: RideMotion.answerPeak)
        let down = RideMotion.progress(phase, from: RideMotion.answerPeak, to: RideMotion.answerEnd)
        let lift = phase < RideMotion.answerPeak ? up : 1 - down
        return 1 + CGFloat((RideMotion.answerScale - 1) * lift)
    }
}

/// Your stop's pin, its ring answering the train's pulse once your stop is next, and at your stop the check: the pin goes
/// and the check pops in 450 ms after the train got there, its tick drawing on 120 ms later, with one ring.
private struct YourStopMarker: View {
    let isComplete: Bool
    /// The loop's length while the ring answers the pulse.
    let answerLoop: Double?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.playsRideMotion) private var playsMotion

    private struct Ring {
        var scale: CGFloat = 1
        var opacity: Double = 0
    }

    var body: some View {
        let plays = playsMotion && !reduceMotion
        let at = plays ? RideMotion.arrivalDelay : 0
        ZStack {
            if let answerLoop {
                PinAnswer(loop: answerLoop)
            }
            RoutePin()
                .fill(TTColor.accent, style: FillStyle(eoFill: true))
                .frame(width: 20, height: 20)
                .opacity(isComplete ? 0 : 1)
                .scaleEffect(isComplete && plays ? 0.6 : 1)
                .animation(.easeOut(duration: 0.2).delay(at), value: isComplete)
            ArrivedCheck(drawn: isComplete ? 1 : 0)
                .animation(plays ? .easeOut(duration: RideMotion.checkDrawDuration).delay(at + RideMotion.checkDrawDelay) : nil, value: isComplete)
                .frame(width: 20, height: 20)
                .opacity(isComplete ? 1 : 0)
                .animation(reduceMotion ? TTMotion.fade : .easeOut(duration: 0.15).delay(at), value: isComplete)
                .scaleEffect(isComplete || !plays ? 1 : 0.6)
                .animation(plays ? RideMotion.pop(duration: 0.38).delay(at) : nil, value: isComplete)
        }
        .keyframeAnimator(initialValue: Ring(), trigger: plays && isComplete) { content, ring in
            content.background {
                Circle()
                    .strokeBorder(TTColor.accent, lineWidth: 2)
                    .frame(width: 20, height: 20)
                    .scaleEffect(ring.scale)
                    .opacity(ring.opacity)
            }
        } keyframes: { _ in
            KeyframeTrack(\.scale) {
                LinearKeyframe(1, duration: RideMotion.arrivalDelay)
                LinearKeyframe(RideMotion.arrivalRingScale, duration: RideMotion.arrivalRingDuration, timingCurve: .easeOut)
            }
            KeyframeTrack(\.opacity) {
                LinearKeyframe(0, duration: RideMotion.arrivalDelay)
                LinearKeyframe(RideMotion.arrivalRingOpacity, duration: 0.01)
                LinearKeyframe(0, duration: RideMotion.arrivalRingDuration, timingCurve: .easeOut)
            }
        }
    }
}

/// Your pin's ring answering the train's pulse (replaces the free-running `PinRing`, TT-224): from 60 % of the loop it shows
/// at 0.75 and spreads to 1.9 as it fades.
private struct PinAnswer: View {
    let loop: Double

    var body: some View {
        TimelineView(.animation) { context in
            let phase = RideMotion.loopPhase(at: context.date.timeIntervalSinceReferenceDate, loop: loop)
            let spread = RideMotion.progress(phase, from: RideMotion.pinAnswerStart, to: 1)
            let eased = 1 - pow(1 - spread, 2)
            Circle()
                .strokeBorder(TTColor.accent, lineWidth: 2)
                .frame(width: 20, height: 20)
                .scaleEffect(1 + (RideMotion.pinAnswerScale - 1) * eased)
                .opacity(phase >= RideMotion.pinAnswerStart ? RideMotion.pinAnswerOpacity * (1 - eased) : 0)
        }
        .frame(width: 20, height: 20)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The check at your stop: a 20 pt accent disc with its tick stroked on as `drawn` goes from 0 to 1 (the board's SVG check,
/// `M7.4 12.4 l3.1 3.1 6.1-6.4` in its 20 pt circle).
private struct ArrivedCheck: View {
    /// The trimmed tick animates on its own (a trimmed shape is animatable), so this view needs no `Animatable`.
    var drawn: Double

    var body: some View {
        ZStack {
            Circle().fill(TTColor.accent)
            Tick()
                .trim(from: 0, to: drawn)
                .stroke(TTColor.onAccent, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
        }
    }

    private struct Tick: Shape {
        func path(in rect: CGRect) -> Path {
            let scale = min(rect.width, rect.height) / 20
            var path = Path()
            path.move(to: CGPoint(x: 5.4 * scale, y: 10.4 * scale))
            path.addLine(to: CGPoint(x: 8.5 * scale, y: 13.5 * scale))
            path.addLine(to: CGPoint(x: 14.6 * scale, y: 7.1 * scale))
            return path.offsetBy(dx: rect.minX, dy: rect.minY)
        }
    }
}

/// The train on the rail: the 28 pt glyph in the accent with a soft accent shadow, on a 26 pt surface disc that hides the
/// rail under it. No green background (Live-Spec). While it moves, a halo leaves it once a loop (0.7 to 1.95, 0.3 to 0 by
/// 46 % of the loop).
private struct TrainMarker: View {
    var loop: Double?

    var body: some View {
        ZStack {
            if let loop {
                TimelineView(.animation) { context in
                    let phase = RideMotion.loopPhase(at: context.date.timeIntervalSinceReferenceDate, loop: loop)
                    let spread = RideMotion.progress(phase, from: 0, to: RideMotion.haloEnd)
                    let eased = 1 - pow(1 - spread, 2)
                    let range = RideMotion.haloScale
                    Circle()
                        .fill(TTColor.accent)
                        .frame(width: 30, height: 30)
                        .scaleEffect(range.lowerBound + (range.upperBound - range.lowerBound) * eased)
                        .opacity(RideMotion.haloOpacity * (1 - spread))
                }
                .allowsHitTesting(false)
            }
            Circle()
                .fill(TTColor.surface)
                .frame(width: 26, height: 26)
            TrainGlyph()
                .fill(TTColor.accent, style: FillStyle(eoFill: true))
                .frame(width: 28, height: 28)
                .shadow(color: TTColor.accent.opacity(0.22), radius: 1, x: 0, y: 1)
        }
    }
}

// MARK: Permission sheet

/// The first "I'm on board" (*Live-Permission*; one straight ask since TT-205, D93, board 5): "Train Times needs your
/// location", one line, Allow location (on to the iOS prompt) and Not now (starts nothing). Shown only while the app still
/// has to ask iOS.
struct RideIntroSheet: View {
    var onContinue: () -> Void = {}
    var onNotNow: () -> Void = {}

    static let height: CGFloat = PermissionAsk.height

    var body: some View {
        PermissionAsk(
            title: "loc.title", line: "loc.subtitle", action: "loc.allow",
            actionID: "onboard.intro.continue", laterID: "onboard.intro.later",
            onAction: onContinue, onLater: onNotNow
        )
        .accessibilityIdentifier("sheet.onboardIntro")
    }
}

/// The two location asks' one shape (TT-205, boards 5 and 16): the pin in its soft tile, a title, one line, the accent
/// button and Not now. No bullets, no footnote.
struct PermissionAsk: View {
    let title: LocalizedStringKey
    let line: LocalizedStringKey
    let action: LocalizedStringKey
    let actionID: String
    let laterID: String
    var onAction: () -> Void = {}
    var onLater: () -> Void = {}

    static let height: CGFloat = 400

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 6) {
                OutlinePin()
                    .frame(width: 34, height: 34)
                    .foregroundStyle(TTColor.accent)
                    .frame(width: 64, height: 64)
                    .background(TTColor.accentSoft, in: RoundedRectangle(cornerRadius: 20))
                    .padding(.bottom, TTSpace.s2)
                    .accessibilityHidden(true)
                Text(title)
                    .font(TTFont.route)
                    .tracking(-0.5)
                    .foregroundStyle(TTColor.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(line)
                    .font(TTFont.subhead)
                    .foregroundStyle(TTColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, TTSpace.s2)
            .padding(.top, TTSpace.s1)
            .padding(.bottom, TTSpace.s2)

            Button(action: onAction) {
                Text(action).frame(maxWidth: .infinity).frame(height: 52)
            }
            .buttonStyle(.ttGlassPrimary)
            .accessibilityIdentifier(actionID)

            Button(action: onLater) {
                Text("loc.later").foregroundStyle(TTColor.inkSecondary)
            }
            .buttonStyle(.ttText)
            .accessibilityIdentifier(laterID)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, TTSpace.s5)
        .padding(.top, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(TTColor.canvas)
        .presentationDetents([.height(Self.height)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(TTRadius.sheet)
        .presentationBackground(TTColor.canvas)
    }
}

/// The permission sheet's outline pin with a filled centre, in a 24 unit box.
struct OutlinePin: View {
    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 24
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * scale, y: y * scale) }
            var pin = Path()
            pin.move(to: point(12, 21.5))
            pin.addCurve(to: point(5.5, 10.3), control1: point(12, 21.5), control2: point(5.5, 15.6))
            pin.addRelativeArc(center: point(12, 10.3), radius: 6.5 * scale, startAngle: .degrees(180), delta: .degrees(180))
            pin.addCurve(to: point(12, 21.5), control1: point(18.5, 15.6), control2: point(12, 21.5))
            pin.closeSubpath()
            context.stroke(pin, with: .foreground, style: StrokeStyle(lineWidth: 2 * scale, lineJoin: .round))
            let centre = CGRect(x: (12 - 2.4) * scale, y: (10.2 - 2.4) * scale, width: 4.8 * scale, height: 4.8 * scale)
            context.fill(Path(ellipseIn: centre), with: .foreground)
        }
    }
}
