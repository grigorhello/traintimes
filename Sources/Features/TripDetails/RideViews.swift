import SwiftUI

/// Trip details in ride mode (TT-172, *Live-Ride*): the ride card, the stops header, the stop list with the train riding its
/// rail, and the footnote. The rows rise into place when the sheet opens on a ride.
struct RideContent: View {
    let ride: RideDetails
    /// False when the ride takes the departure card's place (TT-177, D69): the rows are there in the same update, with
    /// no rise, so the sheet never shows empty between the two.
    var risesIn = true

    @Environment(\.playsRideMotion) private var playsMotion
    @State private var hasRisen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RideCard(ride: ride)
                .modifier(RideRise(order: 0, hasRisen: settled))
            HStack(alignment: .firstTextBaseline) {
                Text(ride.stopsHeader).accessibilityAddTraits(.isHeader)
                Spacer()
                Text(ride.stopsBasis)
            }
            .font(TTFont.footnote)
            .foregroundStyle(TTColor.inkSecondary)
            .padding(.horizontal, TTSpace.s1)
            .padding(.top, TTSpace.s4)
            .modifier(RideRise(order: 1, hasRisen: settled))
            RideStopList(ride: ride)
                .padding(.top, 6)
                .modifier(RideRise(order: 2, hasRisen: settled))
            Text(ride.footnote)
                .font(TTFont.footnote)
                .foregroundStyle(TTColor.inkSecondary)
                .padding(.horizontal, TTSpace.s1)
                .padding(.top, 10)
                .modifier(RideRise(order: 3, hasRisen: settled))
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

// MARK: Ride card

/// The ride card: what is next and how long to it, your stop while it is two or more stops away, and where the position
/// comes from. Arriving and at your stop tint it and press it in.
struct RideCard: View {
    let ride: RideDetails

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let nameFont = Font.system(size: 28, weight: .bold)
    private static let yourStopRow: CGFloat = 60
    private static let statusRow: CGFloat = 44

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: TTRadius.xl)
        VStack(spacing: 0) {
            block
            if let yours = ride.yourStop {
                hairline
                yourStop(yours)
            }
            hairline
            status
        }
        .padding(.horizontal, TTSpace.s4)
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

    private var hairline: some View {
        Rectangle()
            .fill(ride.isTinted ? TTColor.accent.opacity(colorScheme == .dark ? 0.18 : 0.16) : TTColor.hairline)
            .frame(height: 1)
    }

    /// "Next stop", the station, the line under it; the countdown and its time on the right.
    private var block: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(ride.label)
                .font(ride.isTinted ? TTFont.footnote.weight(.semibold) : TTFont.footnote)
                .foregroundStyle(ride.isTinted ? TTColor.accent : TTColor.inkSecondary)
                .lineLimit(1)
            HStack(alignment: .center, spacing: TTSpace.s3) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: ride.name)
                        .font(Self.nameFont)
                        .tracking(-0.6)
                        .foregroundStyle(ride.isTinted ? TTColor.accent : TTColor.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .id(ride.name)
                        .transition(rise)
                    Text(ride.detail)
                        .font(TTFont.subhead)
                        .monospacedDigit()
                        .foregroundStyle(TTColor.inkSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: -2) {
                    Text(ride.countdown)
                        .font(TTFont.timeLead)
                        .tracking(-0.6)
                        .monospacedDigit()
                        .foregroundStyle(TTColor.accent)
                        .contentTransition(.numericText(countsDown: true))
                    Text(ride.countdownTime)
                        .font(TTFont.footnote)
                        .monospacedDigit()
                        .foregroundStyle(TTColor.inkSecondary)
                }
                .lineLimit(1)
                .fixedSize()
            }
            .animation(reduceMotion ? TTMotion.fade : RideMotion.rise, value: ride.name)
            .animation(.easeOut(duration: 0.15), value: ride.countdown)
        }
        .padding(.top, TTSpace.s4)
        .padding(.bottom, 14)
    }

    /// The next stop's name slides up 12 pt as it fades in.
    private var rise: AnyTransition {
        reduceMotion ? .opacity : .asymmetric(insertion: .offset(y: 12).combined(with: .opacity), removal: .opacity)
    }

    private func yourStop(_ yours: RideDetails.YourStop) -> some View {
        HStack(spacing: TTSpace.s3) {
            RoutePin()
                .fill(TTColor.accent, style: FillStyle(eoFill: true))
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text("onboard.yourStop")
                    .font(TTFont.footnote)
                    .foregroundStyle(TTColor.inkSecondary)
                Text(verbatim: yours.name)
                    .font(TTFont.headline)
                    .foregroundStyle(TTColor.ink)
            }
            .lineLimit(1)
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 0) {
                Text(yours.minutes)
                    .font(TTFont.headline)
                    .foregroundStyle(TTColor.ink)
                    .contentTransition(.numericText(countsDown: true))
                Text(yours.time)
                    .font(TTFont.footnote)
                    .foregroundStyle(TTColor.inkSecondary)
            }
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
            .animation(.easeOut(duration: 0.15), value: yours.minutes)
        }
        .frame(height: Self.yourStopRow)
    }

    /// The Live dot and "Live · your location", or "Timetable" with the grey dot, or "Ride complete"; how fresh on the right.
    private var status: some View {
        HStack(spacing: TTSpace.s3) {
            HStack(spacing: TTSpace.s2) {
                switch ride.source {
                case .live(let text):
                    LiveDot()
                    Text(Self.lead(text))
                case .timetable:
                    LiveDot(isLive: false)
                    Text("onboard.live.timetable")
                        .font(TTFont.subhead.weight(.semibold))
                        .foregroundStyle(TTColor.inkSecondary)
                case .complete:
                    Text("onboard.complete")
                        .font(TTFont.subhead.weight(.semibold))
                        .foregroundStyle(TTColor.accent)
                }
            }
            .lineLimit(1)
            Spacer(minLength: 0)
            if let freshness = ride.freshness {
                Text(freshness)
                    .font(TTFont.footnote)
                    .monospacedDigit()
                    .foregroundStyle(TTColor.inkSecondary)
                    .lineLimit(1)
            }
        }
        .frame(height: Self.statusRow)
    }

    /// "Live" semibold in the accent, the rest after it regular in ink-secondary: the copy is one string, split at its
    /// first " · ".
    static func lead(_ text: String) -> AttributedString {
        var styled = AttributedString(text)
        styled.font = TTFont.subhead
        styled.foregroundColor = TTColor.inkSecondary
        let end = styled.range(of: " · ")?.lowerBound ?? styled.endIndex
        styled[styled.startIndex..<end].font = TTFont.subhead.weight(.semibold)
        styled[styled.startIndex..<end].foregroundColor = TTColor.accent
        return styled
    }
}

// MARK: Stop list

/// The stops from yours back to where you got on, on one rail that turns green behind the train; the train's marker glides
/// along it. Your stop is tinted once it is next, its pin rings until the train stops there, and turns into a tick.
struct RideStopList: View {
    let ride: RideDetails

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let row: CGFloat = 44
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
        .padding(.vertical, 6)
        .ttSheetCard()
        .animation(reduceMotion ? nil : RideMotion.glide, value: ride.trainPosition)
        .animation(RideMotion.tint, value: ride.highlightsYourStop)
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

    /// Your stop's row in accent soft, 10 pt wider than the rows on each side and 3 pt in from their edges, from your stop
    /// next until the sheet closes.
    private var yourStopTint: some View {
        let index = ride.stops.firstIndex(where: \.isYours) ?? max(0, ride.stops.count - 1)
        return RoundedRectangle(cornerRadius: TTRadius.md)
            .fill(TTColor.accentSoft)
            .frame(height: Self.row - 6)
            .padding(.horizontal, -10)
            .offset(y: Self.row * CGFloat(index) + 3)
            .opacity(ride.highlightsYourStop ? 1 : 0)
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
        return HStack(spacing: TTSpace.s3) {
            marker(stop)
                .frame(width: Self.markerColumn, height: Self.row)
            Text(verbatim: stop.name)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: TTSpace.s2)
            Text(stop.time)
                .monospacedDigit()
        }
        .font(isBold ? TTFont.headline : TTFont.body)
        .foregroundStyle(colour)
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

/// The canvas's train front: a body with a window and two lamps cut out, and the rail under it, in a 100 unit box.
struct TrainGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 100
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale)
        }
        func box(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
            CGRect(origin: point(x, y), size: CGSize(width: width * scale, height: height * scale))
        }
        var path = Path()
        path.addPath(
            Path(
                roundedRect: box(18, 18, 64, 62),
                cornerRadii: RectangleCornerRadii(
                    topLeading: 18 * scale, bottomLeading: 10 * scale, bottomTrailing: 10 * scale, topTrailing: 18 * scale
                )
            )
        )
        path.addPath(Path(roundedRect: box(28, 30, 44, 22), cornerRadius: 5 * scale))
        path.addEllipse(in: box(30, 60, 12, 12))
        path.addEllipse(in: box(58, 60, 12, 12))
        path.addPath(Path(roundedRect: box(24, 86, 52, 7), cornerRadius: 3.5 * scale))
        return path
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
private struct OutlinePin: View {
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
