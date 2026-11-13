import SwiftUI

/// Trip details in ride mode (TT-204, D87, *Live-Ride-Lean*): the hero card with the minutes to your stop, and the stop
/// list with the train riding its rail. The two rise into place when the sheet opens on a ride.
struct RideContent: View {
    let ride: RideDetails
    /// False when the ride takes the departure card's place (TT-177, D69): the rows are there in the same update, with
    /// no rise, so the sheet never shows empty between the two.
    var risesIn = true

    @Environment(\.playsRideMotion) private var playsMotion
    @State private var hasRisen = false

    var body: some View {
        VStack(alignment: .leading, spacing: TTSpace.s3) {
            RideHero(ride: ride)
                .modifier(RideRise(order: 0, hasRisen: settled))
            RideStopList(ride: ride)
                .modifier(RideRise(order: 1, hasRisen: settled))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { hasRisen = true }
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
            Text(ride.countdown)
                .font(TTFont.rideMinutes)
                .tracking(-2)
                .monospacedDigit()
                .foregroundStyle(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(height: 68)
                .padding(.leading, -2)
                .contentTransition(.numericText(countsDown: true))
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
        .keyframeAnimator(initialValue: 1.0, trigger: pressTrigger) { content, scale in
            content.scaleEffect(scale, anchor: .bottomLeading)
        } keyframes: { _ in
            KeyframeTrack(\.self) {
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

    /// Arriving and at your stop each press the card in once; not with Reduce Motion.
    private var pressTrigger: RideDetails.Moment? { ride.isTinted && !reduceMotion ? ride.moment : nil }

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

// MARK: Stop list

/// The rail from where you got on to your stop (`RideDetails.rows`): passed stops before the last one, and stops between
/// the second one ahead and yours, fold into a short dotted row, so your stop stays on screen on a long trip. The rail turns
/// green behind the train, which stands on a stop's dot or rides half way between two, never on your stop's pin. Your
/// stop's row is always tinted; its pin rings once it is next and turns into a check in a filled circle when the train
/// stops there. Passed stops have no time.
struct RideStopList: View {
    let ride: RideDetails

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let row: CGFloat = 50
    static let fold: CGFloat = 26
    private static let markerColumn: CGFloat = 20
    private static let rail: CGFloat = 2
    private static let marker: CGFloat = 30

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(zip(ride.rows.indices, ride.rows)), id: \.1.id) { index, row in
                switch row {
                case .stop(let stop): stopRow(stop)
                case .fold: foldRow(top: tops[index])
                }
            }
        }
        .background(alignment: .topLeading) {
            // Your stop's tint lies under the rail, so the rail runs on into its pin.
            ZStack(alignment: .topLeading) {
                yourStopTint
                rail
            }
        }
        .overlay(alignment: .topLeading) { train }
        .padding(.horizontal, TTSpace.s4)
        .padding(.vertical, TTSpace.s2)
        .ttSheetCard()
        .animation(reduceMotion ? nil : RideMotion.glide, value: ride.trainPosition)
        .animation(reduceMotion ? nil : RideMotion.glide, value: ride.rows)
    }

    // MARK: Geometry

    private func height(_ row: RideDetails.Row) -> CGFloat {
        if case .fold = row { return Self.fold }
        return Self.row
    }

    /// The top of each drawn row.
    private var tops: [CGFloat] {
        var top: CGFloat = 0
        return ride.rows.map { row in
            defer { top += height(row) }
            return top
        }
    }

    private var totalHeight: CGFloat { ride.rows.reduce(0) { $0 + height($1) } }

    /// The centre of the row that draws stop `index`; nil when it is folded away.
    private func centre(ofStop index: Int) -> CGFloat? {
        guard let row = ride.rows.firstIndex(where: { $0.stopIndex == index }) else { return nil }
        return tops[row] + Self.row / 2
    }

    /// The train's centre down the rail: on its stop's dot, or that far towards the next drawn stop.
    private var trainY: CGFloat {
        let last = max(0, ride.stops.count - 1)
        let position = ride.trainPosition ?? Double(last)
        let index = min(Int(position), last)
        let from = centre(ofStop: index) ?? Self.row / 2
        let to = centre(ofStop: min(index + 1, last)) ?? from
        return from + (to - from) * CGFloat(position - Double(index))
    }

    // MARK: Layers

    /// Grey from the first row's centre to the last one's, green as far as the train.
    private var rail: some View {
        let start = Self.row / 2
        let end = totalHeight - Self.row / 2
        let filled = ride.trainPosition == nil ? end : trainY
        let x = Self.markerColumn / 2 - Self.rail / 2
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(TTColor.controlBorder.opacity(colorScheme == .dark ? 0.42 : 0.38))
                .frame(width: Self.rail, height: max(0, end - start))
            Rectangle()
                .fill(TTColor.accent)
                .frame(width: Self.rail, height: max(0, filled - start))
        }
        .offset(x: x, y: start)
        .accessibilityHidden(true)
    }

    /// Your stop's row in accent soft, 10 pt wider than the rows on each side and 4 pt in from their edges.
    private var yourStopTint: some View {
        RoundedRectangle(cornerRadius: TTRadius.md)
            .fill(TTColor.accentSoft)
            .frame(height: Self.row - 8)
            .padding(.horizontal, -10)
            .offset(y: totalHeight - Self.row + 4)
            .accessibilityHidden(true)
    }

    /// The train glyph on a surface disc, centred on the rail; gone at your stop.
    private var train: some View {
        TrainMarker()
            .frame(width: Self.marker, height: Self.marker)
            .offset(x: Self.markerColumn / 2 - Self.marker / 2, y: trainY - Self.marker / 2)
            .opacity(ride.trainPosition == nil ? 0 : 1)
            .animation(.easeOut(duration: 0.2), value: ride.trainPosition == nil)
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
            Text(verbatim: stop.name)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(colour)
            Spacer(minLength: TTSpace.s2)
            if let time = stop.time {
                Text(time)
                    .monospacedDigit()
                    .foregroundStyle(timeColour)
            }
        }
        .font(isBold ? TTFont.headline : TTFont.body)
        .frame(height: Self.row)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("trip.ride.stop.\(stop.id)")
    }

    /// Stops left out: three dots on a surface gap in the rail, green when the train has passed them.
    private func foldRow(top: CGFloat) -> some View {
        let isPassed = ride.trainPosition == nil || trainY > top + Self.fold / 2
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
            ZStack {
                if ride.isComplete {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(TTColor.onAccent)
                        .frame(width: 20, height: 20)
                        .background(TTColor.accent, in: Circle())
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity))
                } else {
                    if ride.pingsYourStop { PinRing() }
                    RoutePin()
                        .fill(TTColor.accent, style: FillStyle(eoFill: true))
                        .frame(width: 20, height: 20)
                        .transition(.opacity)
                }
            }
            .animation(reduceMotion ? TTMotion.fade : RideMotion.tick, value: ride.isComplete)
        } else {
            let size: CGFloat = stop.isFirst ? 12 : stop.isNext ? 10 : 8
            Circle()
                .fill(stop.isNext ? TTColor.ink : stop.isDone ? TTColor.accent : TTColor.controlBorder)
                .frame(width: size, height: size)
                .padding(2)
                .background(TTColor.surface, in: Circle())
        }
    }
}

/// The train on the rail: the 28 pt glyph in the accent with a soft accent shadow, on a 26 pt surface disc that hides the
/// rail under it. No green background (Live-Spec).
private struct TrainMarker: View {
    var body: some View {
        ZStack {
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

/// The first "I'm on board" (*Live-Permission*): what On board does with location, before iOS asks. Continue goes on to the
/// iOS prompt; Not now starts nothing.
struct RideIntroSheet: View {
    /// "Clarkson", in the second point.
    let destination: String
    var onContinue: () -> Void = {}
    var onNotNow: () -> Void = {}

    static let height: CGFloat = 608

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
                Text("loc.title")
                    .font(.system(size: 22, weight: .bold))
                    .tracking(-0.5)
                    .foregroundStyle(TTColor.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("loc.subtitle")
                    .font(TTFont.subhead)
                    .foregroundStyle(TTColor.inkSecondary)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, TTSpace.s2)
            .padding(.top, TTSpace.s1)
            .padding(.bottom, 2)

            VStack(alignment: .leading, spacing: TTSpace.s3) {
                point("tram.fill", Self.bold(String(localized: "loc.point.next")))
                point("bell.fill", Self.bold(String(format: String(localized: "loc.point.tap"), destination)))
                point("checkmark", Self.bold(String(localized: "loc.point.stops")))
            }
            .padding(.horizontal, TTSpace.s2)
            .padding(.top, TTSpace.s1)
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("loc.note")
                .font(TTFont.footnote)
                .foregroundStyle(TTColor.inkSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, TTSpace.s2)

            Button(action: onContinue) {
                Text("loc.continue").frame(maxWidth: .infinity).frame(height: 52)
            }
            .buttonStyle(.ttGlassPrimary)
            .accessibilityIdentifier("onboard.intro.continue")

            Button(action: onNotNow) {
                Text("loc.later").foregroundStyle(TTColor.inkSecondary)
            }
            .buttonStyle(.ttText)
            .accessibilityIdentifier("onboard.intro.later")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, TTSpace.s5)
        .padding(.top, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(TTColor.canvas)
        .accessibilityIdentifier("sheet.onboardIntro")
        .presentationDetents([.height(Self.height)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(TTRadius.sheet)
        .presentationBackground(TTColor.canvas)
    }

    private func point(_ symbol: String, _ text: AttributedString) -> some View {
        HStack(alignment: .top, spacing: TTSpace.s3) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(TTColor.accent)
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
            Text(text)
                .font(TTFont.subhead)
                .foregroundStyle(TTColor.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The copy's `**lead**` in semibold.
    static func bold(_ markdown: String) -> AttributedString {
        var text = (try? AttributedString(markdown: markdown)) ?? AttributedString(markdown)
        let leads = text.runs.filter { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true }.map(\.range)
        for range in leads {
            text[range].font = TTFont.subhead.weight(.semibold)
        }
        return text
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
