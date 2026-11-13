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

/// The hero card: a 17 pt kicker over the 64 pt minutes to your stop, and "5 min late" under them when late. Arriving and
/// at your stop tint it and press it in. A new kicker rises 10 pt as it fades in; the number changes in place.
struct RideHero: View {
    let ride: RideDetails

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.playsRideMotion) private var playsMotion

    private static let lineFont = TTFont.headline

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: TTRadius.xl)
        VStack(alignment: .leading, spacing: 0) {
            Text(ride.kicker)
                .font(Self.lineFont)
                .tracking(-0.4)
                .foregroundStyle(ride.isKickerAccent ? TTColor.accent : TTColor.inkSecondary)
                .lineLimit(1)
                .id(ride.kicker)
                .transition(kickerRise)
            Text(ride.countdown)
                .font(TTFont.rideMinutes)
                .tracking(-2)
                .monospacedDigit()
                .foregroundStyle(TTColor.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(height: 68)
                .padding(.leading, -2)
                .contentTransition(.numericText(countsDown: true))
            if let late = ride.late {
                Text(late)
                    .font(Self.lineFont)
                    .tracking(-0.4)
                    .monospacedDigit()
                    .foregroundStyle(TTColor.delayInk)
                    .lineLimit(1)
                    .padding(.top, 2)
            }
        }
        .animation(playsMotion && !reduceMotion ? RideMotion.rise : nil, value: ride.kicker)
        .animation(.easeOut(duration: 0.15), value: ride.countdown)
        .padding(.top, 18)
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

/// The stops from where you got on to yours, on one rail that turns green behind the train; the train's marker glides
/// along it. Your stop's row is always tinted; its pin rings once it is next, and turns into a tick when the train stops
/// there (D87). Passed stops have no time.
struct RideStopList: View {
    let ride: RideDetails

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let row: CGFloat = 50
    private static let markerColumn: CGFloat = 20
    private static let rail: CGFloat = 2
    private static let marker: CGFloat = 30

    var body: some View {
        VStack(spacing: 0) {
            ForEach(ride.stops) { stop in
                row(stop)
            }
        }
        .background(alignment: .topLeading) {
            // Your stop's tint lies under the rail, so the rail runs on into its pin (Live-Ride).
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
    }

    /// Grey from the first stop's centre to the last one's, green as far as the train.
    private var rail: some View {
        let length = Self.row * CGFloat(max(0, ride.stops.count - 1))
        let filled = Self.row * CGFloat(min(max(ride.railFill, 0), Double(max(0, ride.stops.count - 1))))
        let x = Self.markerColumn / 2 - Self.rail / 2
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(TTColor.controlBorder.opacity(colorScheme == .dark ? 0.42 : 0.38))
                .frame(width: Self.rail, height: length)
            Rectangle()
                .fill(TTColor.accent)
                .frame(width: Self.rail, height: filled)
        }
        .offset(x: x, y: Self.row / 2)
        .accessibilityHidden(true)
    }

    /// Your stop's row in accent soft, 10 pt wider than the rows on each side and 4 pt in from their edges.
    private var yourStopTint: some View {
        let index = ride.stops.firstIndex(where: \.isYours) ?? max(0, ride.stops.count - 1)
        return RoundedRectangle(cornerRadius: TTRadius.md)
            .fill(TTColor.accentSoft)
            .frame(height: Self.row - 8)
            .padding(.horizontal, -10)
            .offset(y: Self.row * CGFloat(index) + 4)
            .accessibilityHidden(true)
    }

    /// The train glyph on a surface disc, centred on the rail; gone at your stop.
    private var train: some View {
        let position = ride.trainPosition ?? Double(max(0, ride.stops.count - 1))
        return TrainMarker()
            .frame(width: Self.marker, height: Self.marker)
            .offset(
                x: Self.markerColumn / 2 - Self.marker / 2,
                y: Self.row / 2 + Self.row * CGFloat(position) - Self.marker / 2
            )
            .opacity(ride.trainPosition == nil ? 0 : 1)
            .animation(.easeOut(duration: 0.2), value: ride.trainPosition == nil)
            .accessibilityHidden(true)
    }

    private func row(_ stop: RideDetails.Stop) -> some View {
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

    @ViewBuilder private func marker(_ stop: RideDetails.Stop) -> some View {
        if stop.isYours {
            ZStack {
                if ride.isComplete {
                    Image(systemName: "checkmark")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(TTColor.accent)
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
        } else if stop.isFirst {
            Circle()
                .strokeBorder(stop.isDone ? TTColor.accent : TTColor.inkSecondary, lineWidth: 2.5)
                .frame(width: 12, height: 12)
                .background(TTColor.surface, in: Circle())
                .padding(2)
                .background(TTColor.surface, in: Circle())
        } else {
            let size: CGFloat = stop.isNext ? 10 : 8
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
