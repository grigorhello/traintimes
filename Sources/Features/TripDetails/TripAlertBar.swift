import SwiftUI

/// Trip details' alert bar (TT-192, D77; the canvas's *Alert-Trip* and *Alert-Trip-On*): "Alert me", a 52 pt tinted-glass
/// capsule with the bell before the word. One tap turns the alert on in place: the bell pops and the word becomes "Alert on";
/// 0.3 s later the button, still accent, draws in on `TTMotion.drawIn` (no overshoot) and a glass "Repeat" arrives beside
/// it from 0.9, 80 ms later, on `TTMotion.grow`. Repeat shows the days once the alert repeats ("Mon to Fri") and ignores
/// taps for 0.7 s after the tap that turned the alert on, so a double tap on "Alert me" never sets a repeat. A tap on
/// "Alert on" turns it off: Repeat leaves in 120 ms and the button grows back. Reduce Motion: fades.
struct TripAlertBar: View {
    let face: BellFace
    let shakes: Int
    /// "Repeat", or the days.
    let repeatTitle: String
    /// The alert repeats: Repeat's words in ink instead of the accent.
    let repeats: Bool
    /// The day panel is up: Repeat dims to 40 %.
    let isPanelOpen: Bool
    let onAlert: () -> Void
    let onRepeat: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// "Alert on" has drawn in and Repeat stands beside it.
    @State private var drawnIn: Bool
    /// When the word became "Alert on" in this sheet: the draw-in waits for 0.3 s after it and Repeat for 0.7 s.
    @State private var turnedOnAt: Date?

    static let height: CGFloat = 52
    static let repeatWidth: CGFloat = 140
    static let gap: CGFloat = 10
    /// The word holds this long as "Alert on" before the button draws in.
    static let hold: TimeInterval = 0.3
    /// Repeat ignores taps this long after the tap that turned the alert on.
    static let repeatGuard: TimeInterval = 0.7

    init(
        face: BellFace, shakes: Int, repeatTitle: String, repeats: Bool, isPanelOpen: Bool,
        onAlert: @escaping () -> Void, onRepeat: @escaping () -> Void
    ) {
        self.face = face
        self.shakes = shakes
        self.repeatTitle = repeatTitle
        self.repeats = repeats
        self.isPanelOpen = isPanelOpen
        self.onAlert = onAlert
        self.onRepeat = onRepeat
        // Opened on an alert that is on: drawn in from the first frame.
        _drawnIn = State(initialValue: face == .on)
    }

    private var isOn: Bool { face == .on || face == .waiting }

    var body: some View {
        ZStack(alignment: .trailing) {
            repeatButton
            mainButton
                .padding(.trailing, drawnIn ? Self.repeatWidth + Self.gap : 0)
                .animation(reduceMotion ? TTMotion.fade : TTMotion.drawIn, value: drawnIn)
        }
        .frame(height: Self.height)
        .onChange(of: isOn) { _, isOn in
            if isOn { turnedOnAt = .now }
        }
        .task(id: face) { await follow(face) }
    }

    /// Draws in once the alert is on, after the word's hold; grows back once it is off. The wait while saving keeps it as it
    /// is.
    private func follow(_ face: BellFace) async {
        if face == .on, !drawnIn {
            if let turnedOnAt {
                let wait = Self.hold - Date.now.timeIntervalSince(turnedOnAt)
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            }
            guard !Task.isCancelled else { return }
            drawnIn = true
        } else if !isOn, drawnIn {
            drawnIn = false
        }
    }

    private var mainButton: some View {
        Button(action: onAlert) {
            HStack(spacing: TTSpace.s2) {
                // The card's bell and its pop, in white (D62, D72); the bar takes the tap.
                AlertBellButton(
                    face: face, shakes: shakes, label: Text(verbatim: ""), glyph: 20, target: 22, weight: .semibold,
                    tint: TTColor.onAccent
                ) {}
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                ZStack(alignment: .leading) {
                    // The words trade places: the old one leaves in 70 ms, the new one arrives over 120 ms from 80 ms.
                    Text("button.alert_me")
                        .animation(isOn ? Self.leave : Self.arrive) { $0.opacity(isOn ? 0 : 1) }
                    Text("button.alert_on")
                        .animation(isOn ? Self.arrive : Self.leave) { $0.opacity(isOn ? 1 : 0) }
                }
                .font(TTFont.headline)
                .tracking(-0.4)
                .lineLimit(1)
                .fixedSize()
            }
            .foregroundStyle(TTColor.onAccent)
            .frame(maxWidth: .infinity)
            .frame(height: Self.height)
            .ttGlass(tint: TTColor.accent, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(Text(isOn ? "button.alert_on" : "button.alert_me"))
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier("trip.alert")
    }

    private var repeatButton: some View {
        Button {
            if let turnedOnAt, Date.now.timeIntervalSince(turnedOnAt) < Self.repeatGuard { return }
            onRepeat()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "repeat")
                    .font(.system(size: 15, weight: .semibold))
                    .accessibilityHidden(true)
                Text(verbatim: repeatTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .tracking(-0.2)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(repeats ? TTColor.ink : TTColor.accent)
            .padding(.horizontal, TTSpace.s3)
            .frame(width: Self.repeatWidth, height: Self.height)
            .ttGlass(in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
        // From 0.9 at its trailing edge, 80 ms after the button starts drawing in; it leaves in 120 ms.
        .animation(drawnIn ? TTMotion.grow.delay(0.08) : .easeIn(duration: 0.12)) {
            $0.scaleEffect(drawnIn || reduceMotion ? 1 : 0.9, anchor: .trailing)
        }
        .animation(drawnIn ? .easeOut(duration: 0.15).delay(isPanelOpen ? 0 : 0.08) : .easeIn(duration: 0.12)) {
            $0.opacity(drawnIn ? (isPanelOpen ? 0.4 : 1) : 0)
        }
        .allowsHitTesting(drawnIn)
        .accessibilityHidden(!drawnIn)
        .accessibilityIdentifier("trip.repeat")
    }

    private static let leave = Animation.easeIn(duration: 0.07)
    private static let arrive = Animation.easeOut(duration: 0.12).delay(0.08)
}
