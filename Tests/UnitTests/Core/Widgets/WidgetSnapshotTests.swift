import SnapshotTesting
import SwiftUI
import XCTest
@testable import TrainTimes

/// The Home Screen widgets (TT-183) against the Widgets canvas: every state of Next train (board Widgets-States) and
/// Departures (two rows since TT-257, D131, board "Commute first" 6; Widgets-Home-Lean and -Dark before), light and dark, each at its size on the iPhone 17 Pro (`WidgetFixtures.small`
/// and `.medium`, measured by TT-185; the boards drew 158 pt and 338 × 158 pt), with the countdown stopped at the entry's
/// moment. The surface colour stands for the background iOS gives the widget. Also where iOS takes the colours away (the
/// outline tile) and StandBy (no background, on black). One reference per state, named after it.
final class WidgetSnapshotTests: XCTestCase {
    @MainActor func testNextTrainLight() { snap(.nextTrain, trains, .light) }
    @MainActor func testNextTrainDark() { snap(.nextTrain, trains, .dark) }
    @MainActor func testNextTrainMessagesLight() { snap(.nextTrain, messages, .light) }
    @MainActor func testNextTrainMessagesDark() { snap(.nextTrain, messages, .dark) }
    // Departures has no "Your train": that state draws the same as the first one.
    @MainActor func testDeparturesLight() { snap(.departures, trains.filter { $0.0 != "your-train" }, .light) }
    @MainActor func testDeparturesDark() { snap(.departures, trains.filter { $0.0 != "your-train" }, .dark) }
    @MainActor func testDeparturesMessagesLight() { snap(.departures, messages, .light) }
    @MainActor func testDeparturesMessagesDark() { snap(.departures, messages, .dark) }

    // My trains (TT-257, D131; board "Commute first" 6): the saved trains on both routes.
    @MainActor func testMyTrainsNextTrainLight() { snap(.nextTrain, mine, .light) }
    @MainActor func testMyTrainsNextTrainDark() { snap(.nextTrain, mine, .dark) }
    @MainActor func testMyTrainsDeparturesLight() { snap(.departures, mine, .light) }
    @MainActor func testMyTrainsDeparturesDark() { snap(.departures, mine, .dark) }

    /// A tinted Home Screen draws the widget in one colour, so the tile is an outline; StandBy removes the background.
    @MainActor func testWithoutColourAndWithoutBackground() {
        let outline = WidgetLook(isFullColor: false, showsBackground: false)
        let standBy = WidgetLook(isFullColor: true, showsBackground: false)
        snap(.nextTrain, WidgetFixtures.nextTrain(), "outline", .dark, look: outline)
        snap(.departures, WidgetFixtures.nextTrain(), "outline", .dark, look: outline)
        snap(.nextTrain, WidgetFixtures.nextTrain(), "stand-by", .dark, look: standBy)
        // My trains, and "now" (drawn twice in one colour, TT-239).
        snap(.departures, WidgetFixtures.mine(WidgetFixtures.at(7, 47)), "mine-outline", .dark, look: outline)
        snap(.departures, WidgetFixtures.leavingNow, "now-outline", .dark, look: outline)
        snap(.nextTrain, WidgetFixtures.leavingNow, "now-outline", .dark, look: outline)
    }

    /// The widest lines: an express at 11:47 PM that is the last train, 2 h 30 min away ("Last train · 2 h 30 min"); the
    /// 24-hour clock; and Departures' widest row, a wait in hours ("in 2 h 43 min", TT-246, D123) beside the route, over
    /// two 24-hour times in "Next" (TT-257, D131).
    @MainActor func testLongLines() {
        var late = WidgetEntry.Trains(header: WidgetFixtures.header(), trains: [WidgetFixtures.train(23, 47, express: true)])
        late.lastTrain = 0
        late.nextDayFirst = WidgetFixtures.train(5, 43, on: WidgetFixtures.day.adding(days: 1))
        let lateEntry = WidgetFixtures.entry(WidgetFixtures.at(21, 17), .trains(late))
        for widget in [WidgetKind.nextTrain, .departures] {
            snap(widget, lateEntry, "late-express", .light)
            snap(widget, WidgetFixtures.nextTrain(format: .twentyFourHour), "24-hour", .light)
        }
        var early = WidgetEntry.Trains(
            header: WidgetFixtures.header(),
            trains: [WidgetFixtures.train(12, 43), WidgetFixtures.train(13, 13), WidgetFixtures.train(13, 43)]
        )
        early.later = Array(early.trains.dropFirst())
        snap(.departures, WidgetFixtures.entry(WidgetFixtures.at(10, 0), .trains(early), format: .twentyFourHour), "long-wait", .light)
    }

    // MARK: - States

    private var trains: [(String, WidgetEntry)] {
        [
            ("next-train", WidgetFixtures.nextTrain()), ("your-train", WidgetFixtures.yourTrain),
            ("express-next", WidgetFixtures.expressNext), ("leaving-now", WidgetFixtures.leavingNow),
            ("one-later", WidgetFixtures.oneLater), ("last-train", WidgetFixtures.lastTrain), ("evening", WidgetFixtures.evening),
        ]
    }

    /// My trains from `WidgetFixtures.commuteFile()`: the morning, the afternoon turned home, nothing more today (tomorrow,
    /// and Friday evening's Monday), one saved train, two on one route, and none (the open route).
    private var mine: [(String, WidgetEntry)] {
        let friday = WidgetFixtures.day.adding(days: 2)
        return [
            ("mine-morning", WidgetFixtures.mine(WidgetFixtures.at(7, 47))),
            ("mine-afternoon", WidgetFixtures.mine(WidgetFixtures.at(16, 40))),
            ("mine-tomorrow", WidgetFixtures.mine(WidgetFixtures.at(19, 0))),
            ("mine-monday", WidgetFixtures.mine(WidgetFixtures.at(19, 0, on: friday))),
            ("mine-one-saved", WidgetFixtures.mine(WidgetFixtures.at(7, 47), file: WidgetFixtures.commuteFile(saved: ["07:58"]))),
            ("mine-one-route", WidgetFixtures.mine(WidgetFixtures.at(7, 47), file: WidgetFixtures.commuteFile(saved: ["07:58", "08:28"]))),
            ("mine-none", WidgetFixtures.mine(WidgetFixtures.at(7, 47), file: WidgetFixtures.commuteFile(saved: []))),
        ]
    }

    private var messages: [(String, WidgetEntry)] {
        [
            ("after-last-train", WidgetFixtures.afterLastTrain), ("no-trains-today", WidgetFixtures.noTrainsToday),
            ("not-loaded", WidgetFixtures.notLoaded), ("no-route", WidgetFixtures.noRoute), ("out-of-date", WidgetFixtures.outOfDate),
        ]
    }

    // MARK: - Drawing

    @MainActor
    private func snap(
        _ widget: WidgetKind, _ states: [(String, WidgetEntry)], _ style: UIUserInterfaceStyle, testName: String = #function,
        line: UInt = #line
    ) {
        for (name, entry) in states {
            snap(widget, entry, name, style, testName: testName, line: line)
        }
    }

    /// One widget at its size, on the surface colour (on black where iOS removes the background).
    @MainActor
    private func snap(
        _ widget: WidgetKind, _ entry: WidgetEntry, _ name: String, _ style: UIUserInterfaceStyle, look: WidgetLook = WidgetLook(),
        testName: String = #function, line: UInt = #line
    ) {
        let size = widget == .nextTrain ? WidgetFixtures.small : WidgetFixtures.medium
        let content = widget == .nextTrain
            ? AnyView(NextTrainWidgetView(content: NextTrainContent(entry)))
            : AnyView(DeparturesWidgetView(content: DeparturesContent(entry)))
        let view = content
            .environment(\.widgetLook, look)
            .frame(width: size.width, height: size.height)
            .background(look.showsBackground ? TTColor.surface : Color.black)
        let traits = ViewImageConfig.iPhone17Pro.traits.modifyingTraits { $0.userInterfaceStyle = style }
        let failure = verifySnapshot(
            of: view,
            as: .image(perceptualPrecision: 0.98, layout: .fixed(width: size.width, height: size.height), traits: traits),
            named: "\(widget.rawValue).\(name)",
            file: #filePath,
            testName: testName,
            line: line
        )
        if let failure {
            XCTFail("\(name): " + failure.replacingOccurrences(of: "\n", with: " | "), line: line)
        }
    }
}
