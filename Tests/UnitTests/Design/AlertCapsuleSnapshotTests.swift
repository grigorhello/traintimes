import SnapshotTesting
import SwiftUI
import XCTest
@testable import TrainTimes

/// Every alert capsule state and the day panel (TT-191, D71) against the Alerts-Spec board's States and Words, light and
/// dark, on the canvas: Alert on with Repeat, a repeating alert on, Alert off with Undo, a repeating alert off on all days,
/// the three failures with Try again, Notifications are off with Turn on and the hint; the panel with Mon to Fri lit and
/// with no day lit. Glass is off, as in the other control snapshots.
final class AlertCapsuleSnapshotTests: XCTestCase {
    @MainActor func testCapsulesLight() { snap(Capsules(), height: 640, .light) }
    @MainActor func testCapsulesDark() { snap(Capsules(), height: 640, .dark) }
    @MainActor func testDayPanelLight() { snap(Panels(), height: 300, .light) }
    @MainActor func testDayPanelDark() { snap(Panels(), height: 300, .dark) }

    @MainActor
    private func snap(_ view: some View, height: CGFloat, _ style: UIUserInterfaceStyle, testName: String = #function, line: UInt = #line) {
        let traits = UITraitCollection { traits in
            traits.userInterfaceStyle = style
            traits.displayScale = 3
        }
        assertSnapshot(
            of: view.environment(\.rendersGlass, false),
            as: .image(perceptualPrecision: 0.98, layout: .fixed(width: 402, height: height), traits: traits),
            testName: testName,
            line: line
        )
    }
}

@MainActor
private enum CapsuleFixtures {
    static let formatter = TimeFormatter(format: .twelveHour)
    static let trip = AlertFixtures.trip()
    static let today = trip.key.serviceDay

    static func capsule(_ kind: AlertBellModel.Capsule.Kind, repeats: [Int] = [], panelDays: [Int]? = nil) -> AlertBellModel.Capsule {
        AlertBellModel.Capsule(
            id: 1, kind: kind, trip: kind == .hint ? nil : trip, route: AlertFixtures.route, repeats: repeats, panelDays: panelDays
        )
    }

    static func view(_ capsule: AlertBellModel.Capsule) -> AlertCapsuleView {
        AlertCapsuleView(
            glyph: ScheduleView.glyph(capsule.kind),
            words: capsule.words(formatter, today: today),
            action: capsule.actionKey.map { AlertCapsuleView.Action(title: LocalizedStringKey($0)) {} },
            panel: capsule.panelDays.map { days in
                AlertCapsuleView.Panel(words: capsule.panelWords(formatter, today: today), days: days, onToggle: { _ in }, onDone: {})
            },
            panelWidth: 362
        )
    }
}

private struct Capsules: View {
    var body: some View {
        VStack(spacing: TTSpace.s4) {
            CapsuleFixtures.view(CapsuleFixtures.capsule(.on))
            CapsuleFixtures.view(CapsuleFixtures.capsule(.on, repeats: [1, 2, 3, 4, 5]))
            CapsuleFixtures.view(CapsuleFixtures.capsule(.off))
            CapsuleFixtures.view(CapsuleFixtures.capsule(.off, repeats: [1, 2, 3, 4, 5]))
            CapsuleFixtures.view(CapsuleFixtures.capsule(.failed(.turnOn)))
            CapsuleFixtures.view(CapsuleFixtures.capsule(.failed(.changeDays)))
            CapsuleFixtures.view(CapsuleFixtures.capsule(.failed(.turnOff)))
            CapsuleFixtures.view(CapsuleFixtures.capsule(.notificationsOff))
            CapsuleFixtures.view(CapsuleFixtures.capsule(.hint))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TTColor.canvas)
    }
}

private struct Panels: View {
    var body: some View {
        VStack(spacing: TTSpace.s5) {
            CapsuleFixtures.view(CapsuleFixtures.capsule(.on, panelDays: [1, 2, 3, 4, 5]))
            CapsuleFixtures.view(CapsuleFixtures.capsule(.on, panelDays: []))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TTColor.canvas)
    }
}
