import SwiftUI

/// The ride strip under the day strip while a ride runs (TT-172; one line since TT-205, D93, *Live-Schedule*): the Live dot,
/// the ride screen's line ("Clarkson in", "Clarkson is next", "Arriving at Clarkson", "This is Clarkson"), the minutes in
/// the accent, a chevron. A tap opens Trip details in ride mode.
struct RideStripView: View {
    let strip: RideStrip
    var onOpen: () -> Void = {}

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: TTSpace.s2) {
                LiveDot(isLive: strip.isLive)
                Text(strip.line)
                    .font(TTFont.headline)
                    .tracking(-0.4)
                    .foregroundStyle(TTColor.ink)
                    .lineLimit(1)
                Spacer(minLength: TTSpace.s2)
                Text(strip.countdown)
                    .font(TTFont.stripMinutes)
                    .tracking(-0.4)
                    .monospacedDigit()
                    .foregroundStyle(TTColor.accent)
                    .lineLimit(1)
                    .fixedSize()
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.easeOut(duration: 0.15), value: strip.countdown)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(TTColor.inkTertiary)
                    .accessibilityHidden(true)
            }
            .padding(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 12))
            .background(TTColor.accentSoft, in: RoundedRectangle(cornerRadius: TTRadius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: TTRadius.lg)
                    .strokeBorder(TTColor.accent.opacity(colorScheme == .dark ? 0.20 : 0.14), lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: TTRadius.lg))
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("schedule.ride")
    }
}

/// What the strip under the day strip shows (TT-205, D93): the wrong train warning (TT-250, D127), the ride strip, the
/// departure question (TT-231), the automatic ride's one-time strip (TT-243, D120), Automatic direction's one-time strip
/// (TT-236), or the watched-trip strip, in that order: one at a time, so a later one waits for those before it. No
/// countdown before departure: the train's own card says it.
enum RideStripContent: Equatable {
    case wrongTrain, riding, asking, autoRide, direction, otherwise

    /// `warnsWrongTrain`: a wrong train warning shows (`WrongTrain.warning`). `asksDeparture`: the alerted train has left and
    /// Schedule asks "On board?" about it (TT-231). `showsAutoRideStrip`: the automatic ride's one-time strip is due
    /// (`AutoRideStrip.isShown`). `showsDirectionStrip`: Automatic direction's one-time strip is unanswered
    /// (`DirectionLook.showsStrip`).
    init(
        warnsWrongTrain: Bool = false, isRiding: Bool, asksDeparture: Bool = false, showsAutoRideStrip: Bool = false,
        showsDirectionStrip: Bool = false
    ) {
        if warnsWrongTrain {
            self = .wrongTrain
        } else if isRiding {
            self = .riding
        } else if asksDeparture {
            self = .asking
        } else if showsAutoRideStrip {
            self = .autoRide
        } else if showsDirectionStrip {
            self = .direction
        } else {
            self = .otherwise
        }
    }

    /// From On board alone when `autoRide` and `direction` are nil: what Automatic direction's look counts as over Schedule.
    @MainActor init(_ onBoard: OnBoard?, autoRide: AutoRideStrip? = nil, direction: DirectionLook? = nil) {
        self.init(
            warnsWrongTrain: onBoard?.wrongTrainWarning != nil,
            isRiding: onBoard?.activeRide != nil, asksDeparture: onBoard?.asksDeparture ?? false,
            showsAutoRideStrip: autoRide?.isShown ?? false, showsDirectionStrip: direction?.showsStrip ?? false
        )
    }
}

/// The strip under the day strip: the ride strip while a ride runs, the departure question (TT-231), the automatic ride's
/// one-time strip (TT-243), Automatic direction's (TT-236), else `otherwise` (the watched-trip strip). The ride strip drops
/// in 12 pt from under the day strip, from 0.97, on `RideMotion.rise`; the question and the one-time strips land from −10 pt
/// and 0.97 on `RideMotion.press`, and the question folds into the ride strip on `RideMotion.fold` (its Yes, or a ride that
/// started by itself, TT-242). Reduce Motion fades. The
/// ride strip's digits follow its clock each second.
///
/// The strips share one top-aligned `ZStack`, which stays while one replaces another, so the leaving strip fades where it
/// was and the arriving one lands over it (the animation is on the stack, which a `Group` would have handed to the
/// inserted strip, too late for its transition). `otherwise` stays a direct child of the header, as before. Schedule
/// moves the timeline with the strip (`rideStripMotion(_:)`).
struct RideStripSlot<Otherwise: View>: View {
    let onBoard: OnBoard?
    /// The automatic ride's one-time strip (TT-243); nil shows none.
    var autoRide: AutoRideStrip?
    /// Automatic direction's look, for its one-time strip; nil shows none.
    var direction: DirectionLook?
    var onOpen: () -> Void = {}
    @ViewBuilder var otherwise: Otherwise

    @Environment(\.timeFormatter) private var formatter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The question was showing before this change: its Yes folds into the ride strip.
    @State private var wasAsking = false

    var body: some View {
        let content = RideStripContent(onBoard, autoRide: autoRide, direction: direction)
        Group {
            if content == .otherwise {
                otherwise
            } else {
                ZStack(alignment: .top) {
                    strip(content)
                }
                .padding(.horizontal, TTSpace.s5)
                .padding(.top, -2)
                .transition(drop(by: -12))
            }
        }
        .animation(animation(for: content), value: content)
        .onChange(of: content, initial: true) { wasAsking = content == .asking }
    }

    @ViewBuilder
    private func strip(_ content: RideStripContent) -> some View {
        switch content {
        case .wrongTrain:
            if let warning = onBoard?.wrongTrainWarning {
                // A tap on the card itself opens the ride's sheet while a ride runs; its buttons answer.
                WrongTrainCard(
                    display: WrongTrainDisplay(warning, formatter: formatter), size: .strip, id: "schedule.wrongTrain",
                    onTrains: { onBoard?.wrongTrainTrains() },
                    onFine: { onBoard?.wrongTrainFine() }
                )
                .contentShape(RoundedRectangle(cornerRadius: TTRadius.question))
                .onTapGesture { if onBoard?.activeRide != nil { onOpen() } }
                .transition(drop(by: -10))
            }
        case .riding:
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                if let strip = onBoard?.strip(formatter: formatter) {
                    RideStripView(strip: strip, onOpen: onOpen)
                }
            }
            .transition(drop(by: -12))
        case .asking:
            if let ask = onBoard?.departureAsk {
                TrainQuestionCard(
                    departure: ask,
                    onYes: { Task { if await onBoard?.acceptDeparture() == true { onOpen() } } },
                    onNo: { onBoard?.declineDeparture() }
                )
                .transition(drop(by: -10))
            }
        case .autoRide:
            DirectionStripCard.autoRide(onOK: { autoRide?.ok() }, onTurnOff: { autoRide?.turnOff() })
                .transition(drop(by: -10))
        case .direction:
            DirectionStripCard(onOK: { direction?.stripOK() }, onTurnOff: { direction?.stripTurnOff() })
                .transition(drop(by: -10))
        case .otherwise:
            EmptyView()
        }
    }

    private func drop(by offset: CGFloat) -> AnyTransition {
        reduceMotion ? .opacity : .offset(y: offset).combined(with: .scale(scale: 0.97, anchor: .top)).combined(with: .opacity)
    }

    private func animation(for content: RideStripContent) -> Animation {
        if reduceMotion { return TTMotion.fade }
        switch content {
        case .riding: return wasAsking ? RideMotion.fold : RideMotion.rise
        case .wrongTrain, .asking, .autoRide, .direction: return RideMotion.press
        case .otherwise: return RideMotion.rise
        }
    }
}

extension View {
    /// Moves what sits under the header (the timeline) with the strip under the day strip when it changes, on
    /// `RideMotion.fold` (a fade with Reduce Motion), so a strip or the question no longer pushes the timeline down in one
    /// frame. The strip itself keeps its own spring (`RideStripSlot`). Only this modifier reads the strip's state, so a change
    /// does not redraw the screen it wraps. `autoRide` and `direction`: the one-time strips move it too (TT-243, TT-236).
    func rideStripMotion(_ onBoard: OnBoard?, autoRide: AutoRideStrip? = nil, direction: DirectionLook? = nil) -> some View {
        modifier(RideStripMotion(onBoard: onBoard, autoRide: autoRide, direction: direction))
    }
}

private struct RideStripMotion: ViewModifier {
    let onBoard: OnBoard?
    let autoRide: AutoRideStrip?
    let direction: DirectionLook?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(
            reduceMotion ? TTMotion.fade : RideMotion.fold,
            value: RideStripContent(onBoard, autoRide: autoRide, direction: direction)
        )
    }
}
