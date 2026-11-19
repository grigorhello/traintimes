import SnapshotTesting
import SwiftUI
import XCTest
@testable import TrainTimes

/// The Home Screen widgets (TT-183) against the Widgets canvas: every state of Next train (board Widgets-States) and
/// Departures (Widgets-Home-Lean and -Dark), light and dark, each at its size from the boards (158 pt square and
/// 338 × 158 pt, until TT-185 measures the simulator's), with the countdown stopped at the entry's moment. The surface
/// colour stands for the background iOS gives the widget. Also where iOS takes the colours away (the outline tile),
/// StandBy (no background, on black) and iOS 17 (no countdown). One reference per state, named after it.
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

    /// A tinted Home Screen draws the widget in one colour, so the tile is an outline; StandBy removes the background.
    @MainActor func testWithoutColourAndWithoutBackground() {
        let outline = WidgetLook(isFullColor: false, showsBackground: false)
        let standBy = WidgetLook(isFullColor: true, showsBackground: false)
        snap(.nextTrain, WidgetFixtures.nextTrain(), "outline", .dark, look: outline)
        snap(.departures, WidgetFixtures.nextTrain(), "outline", .dark, look: outline)
        snap(.nextTrain, WidgetFixtures.nextTrain(), "stand-by", .dark, look: standBy)
    }

    /// Before iOS 18 no text counts down by itself: the clock time only.
    @MainActor func testWithoutTheCountdown() {
        snap(.nextTrain, WidgetFixtures.nextTrain(), "next-train", .light, countsDown: false)
        snap(.nextTrain, WidgetFixtures.lastTrain, "last-train", .light, countsDown: false)
        snap(.departures, WidgetFixtures.nextTrain(), "next-train", .light, countsDown: false)
    }

    /// The widest lines: an express at 11:47 PM that is the last train, 150 min away; the 24-hour clock; and Departures'
    /// widest row, a three-digit wait beside two 24-hour times.
    @MainActor func testLongLines() {
        var late = WidgetEntry.Trains(header: WidgetFixtures.header(), trains: [WidgetFixtures.train(23, 47, express: true)])
        late.lastTrain = 0
        late.nextDayFirst = WidgetFixtures.train(5, 43, on: WidgetFixtures.day.adding(days: 1))
        let lateEntry = WidgetFixtures.entry(WidgetFixtures.at(21, 17), .trains(late))
        for widget in WidgetKind.allCases {
            snap(widget, lateEntry, "late-express", .light)
            snap(widget, WidgetFixtures.nextTrain(format: .twentyFourHour), "24-hour", .light)
        }
        let early = WidgetEntry.Trains(
            header: WidgetFixtures.header(),
            trains: [WidgetFixtures.train(12, 43), WidgetFixtures.train(13, 13), WidgetFixtures.train(13, 43)]
        )
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

    /// One widget at its size, at the entry's moment, on the surface colour (on black where iOS removes the background).
    @MainActor
    private func snap(
        _ widget: WidgetKind, _ entry: WidgetEntry, _ name: String, _ style: UIUserInterfaceStyle, look: WidgetLook = WidgetLook(),
        countsDown: Bool = true, testName: String = #function, line: UInt = #line
    ) {
        let size = widget == .nextTrain ? CGSize(width: 158, height: 158) : CGSize(width: 338, height: 158)
        let content = widget == .nextTrain
            ? AnyView(NextTrainWidgetView(content: NextTrainContent(entry)))
            : AnyView(DeparturesWidgetView(content: DeparturesContent(entry)))
        let view = content
            .environment(\.widgetLook, look)
            .environment(\.widgetCountdownFixedAt, entry.date)
            .environment(\.widgetShowsCountdown, countsDown)
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
