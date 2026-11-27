import SnapshotTesting
import SwiftUI
import XCTest
@testable import TrainTimes

/// Next train's Lock Screen sizes (TT-184) against the "Lock Screen" row of board Widgets-States: every state of the
/// rectangular and the circular at the iPhone 17 Pro's sizes (`WidgetFixtures.lockRectangular`, `lockCircular`, measured
/// by TT-185) and the inline line at the boards' size, one sheet per size, each state under its name. Light, dark, and dimmed as on the Always-On display (no
/// plate, no disc). A flat colour stands for the wallpaper and a faint fill for iOS's own plate, which only the widget
/// extension can draw; the inline's font is iOS's, so the sheet sets the boards' 18 pt.
final class LockWidgetSnapshotTests: XCTestCase {
    @MainActor func testRectangularDark() { rectangular(.dark) }
    @MainActor func testRectangularLight() { rectangular(.light) }
    @MainActor func testRectangularDimmed() { rectangular(.dark, isDimmed: true) }
    @MainActor func testCircularDark() { circular(.dark) }
    @MainActor func testCircularLight() { circular(.light) }
    @MainActor func testCircularDimmed() { circular(.dark, isDimmed: true) }
    @MainActor func testInlineDark() { inline(.dark) }
    @MainActor func testInlineLight() { inline(.light) }
    @MainActor func testMyTrainsDark() { myTrains(.dark) }
    @MainActor func testMyTrainsLight() { myTrains(.light) }

    // MARK: - States

    /// 9:17 PM: the 11:47 PM express is the last train, 2 h 30 min away. The widest "Last train" line, and a clock time too
    /// wide for the circle.
    private var lateExpress: WidgetEntry {
        var late = WidgetEntry.Trains(header: WidgetFixtures.header(), trains: [WidgetFixtures.train(23, 47, express: true)])
        late.lastTrain = 0
        late.nextDayFirst = WidgetFixtures.train(5, 43, on: WidgetFixtures.day.adding(days: 1))
        return WidgetFixtures.entry(WidgetFixtures.at(21, 17), .trains(late))
    }

    /// 11:46:30 PM: the 11:47 leaves in the minute. The widest clock time under "now" in the circle.
    private var leavingLate: WidgetEntry {
        var late = WidgetEntry.Trains(header: WidgetFixtures.header(), trains: [WidgetFixtures.train(23, 47)])
        late.lastTrain = 0
        return WidgetFixtures.entry(WidgetFixtures.at(23, 46, second: 30), .trains(late))
    }

    /// 3:02 PM on the 24-hour clock, long station names: Your train, the 16:58, in 1 h 56 min, the 15:13 before it. The
    /// widest first and third rows.
    private var longYourTrain: WidgetEntry {
        let header = WidgetEntry.Header(
            from: WidgetFile.Stop(id: "WH", name: "West Harbour GO"), to: WidgetFile.Stop(id: "NF", name: "Niagara Falls GO"),
            line: WidgetFixtures.line, link: WidgetLink.route(WidgetFixtures.route)
        )
        var trains = WidgetEntry.Trains(header: header, trains: [WidgetFixtures.train(15, 13), WidgetFixtures.train(16, 58, alerted: true)])
        trains.yourTrain = 1
        trains.earlier = 0
        return WidgetFixtures.entry(WidgetFixtures.at(15, 2), .trains(trains), format: .twentyFourHour)
    }

    /// The same names with no alert: the widest route row.
    private var longRoute: WidgetEntry {
        guard case .trains(var trains) = longYourTrain.state else { return longYourTrain }
        trains.yourTrain = nil
        trains.earlier = nil
        return WidgetFixtures.entry(WidgetFixtures.at(15, 2), .trains(trains), format: .twentyFourHour)
    }

    /// 6:32 AM: Your train, the alerted 8:28, in 1 h 56 min, the 7:58 before it. The widest note that still fits whole
    /// once it shrinks (TT-246, D123).
    private var hoursYourTrain: WidgetEntry {
        var trains = WidgetEntry.Trains(
            header: WidgetFixtures.header(), trains: [WidgetFixtures.train(7, 58), WidgetFixtures.train(8, 28, alerted: true)]
        )
        trains.yourTrain = 1
        trains.earlier = 0
        return WidgetFixtures.entry(WidgetFixtures.at(6, 32), .trains(trains))
    }

    /// 6:04 AM: the 8:00 in 1 h 56 min, then the alerted 8:28, more than 2 h away. At the edge with the bell, which does
    /// not shrink: whole only while it fits shrunk, never cut (TT-246, D123).
    private var hoursThenAlerted: WidgetEntry {
        let trains = WidgetEntry.Trains(
            header: WidgetFixtures.header(), trains: [WidgetFixtures.train(8, 0), WidgetFixtures.train(8, 28, alerted: true)]
        )
        return WidgetFixtures.entry(WidgetFixtures.at(6, 4), .trains(trains))
    }

    private var states: [(String, WidgetEntry)] {
        [
            ("next-train", WidgetFixtures.nextTrain()), ("express-next", WidgetFixtures.expressNext),
            ("your-train", WidgetFixtures.yourTrain), ("hand-over", WidgetFixtures.handOver()),
            ("leaving-now", WidgetFixtures.leavingNow), ("last-train", WidgetFixtures.lastTrain),
            ("after-last-train", WidgetFixtures.afterLastTrain), ("no-trains-today", WidgetFixtures.noTrainsToday),
            ("not-loaded", WidgetFixtures.notLoaded), ("no-route", WidgetFixtures.noRoute),
            ("out-of-date", WidgetFixtures.outOfDate),
        ]
    }

    // MARK: - Sheets

    @MainActor
    private func rectangular(_ style: UIUserInterfaceStyle, isDimmed: Bool = false, testName: String = #function, line: UInt = #line) {
        let entries = states + [
            ("late-express", lateExpress), ("long-your-train", longYourTrain), ("long-route", longRoute),
            ("hours-your-train", hoursYourTrain), ("hours-then-alerted", hoursThenAlerted),
        ]
        let cells = entries.map { name, entry in
            Cell(id: name) {
                LockRectangularView(content: LockRectangularContent(entry), isDimmed: isDimmed) { Color.primary.opacity(0.1) }
            }
        }
        sheet("lock-rectangular", cells, WidgetFixtures.lockRectangular, columns: 2, style, testName: testName, line: line)
    }

    @MainActor
    private func circular(_ style: UIUserInterfaceStyle, isDimmed: Bool = false, testName: String = #function, line: UInt = #line) {
        let far = [
            ("far-train", WidgetFixtures.farTrain()), ("far-24-hour", WidgetFixtures.farTrain(format: .twentyFourHour)),
            ("late-express", lateExpress), ("leaving-late", leavingLate),
        ]
        let entries = states.filter { !["hand-over", "no-route", "out-of-date"].contains($0.0) } + far
        let cells = entries.map { name, entry in
            Cell(id: name) {
                LockCircularView(content: LockCircularContent(entry), isDimmed: isDimmed) { Color.primary.opacity(0.1) }
            }
        }
        sheet("lock-circular", cells, WidgetFixtures.lockCircular, columns: 4, style, cellWidth: 96, testName: testName, line: line)
    }

    /// The inline line at the width beside the date, and in a width too short for "to Union".
    @MainActor
    private func inline(_ style: UIUserInterfaceStyle, testName: String = #function, line: UInt = #line) {
        let entries = states.filter { ["next-train", "your-train", "after-last-train", "no-trains-today", "not-loaded"].contains($0.0) }
        var cells = entries.map { name, entry in
            Cell(id: name) {
                LockInlineView(content: LockInlineContent(entry))
                    .frame(width: 280, alignment: .leading)
            }
        }
        cells.append(
            Cell(id: "next-train-narrow") {
                LockInlineView(content: LockInlineContent(WidgetFixtures.nextTrain()))
                    .frame(width: 130, alignment: .leading)
                    .frame(width: 280, alignment: .leading)
            }
        )
        sheet("lock-inline", cells, CGSize(width: 280, height: 24), columns: 1, style, testName: testName, line: line)
    }

    /// My trains (TT-257, D131; board "Commute first"): the saved 7:58 from 6:30 AM, 40 min before it, handed over in its
    /// last 30 min, and tomorrow's and Monday's; each size on its own sheet.
    @MainActor
    private func myTrains(_ style: UIUserInterfaceStyle, testName: String = #function, line: UInt = #line) {
        let day = WidgetFixtures.day
        let entries = [
            ("mine-early", WidgetFixtures.mine(WidgetFixtures.at(6, 30))),
            ("mine-40-min", WidgetFixtures.mine(WidgetFixtures.at(7, 18))),
            ("mine-hand-over", WidgetFixtures.mine(WidgetFixtures.at(7, 47))),
            ("mine-tomorrow", WidgetFixtures.mine(WidgetFixtures.at(19, 0))),
            ("mine-monday", WidgetFixtures.mine(WidgetFixtures.at(19, 0, on: day.adding(days: 2)))),
            ("mine-one-saved", WidgetFixtures.mine(WidgetFixtures.at(6, 30), file: WidgetFixtures.commuteFile(saved: ["07:58"]))),
        ]
        let rectangles = entries.map { name, entry in
            Cell(id: name) { LockRectangularView(content: LockRectangularContent(entry), isDimmed: false) { Color.primary.opacity(0.1) } }
        }
        sheet("my-trains-rectangular", rectangles, WidgetFixtures.lockRectangular, columns: 2, style, testName: testName, line: line)
        let circles = entries.map { name, entry in
            Cell(id: name) { LockCircularView(content: LockCircularContent(entry), isDimmed: false) { Color.primary.opacity(0.1) } }
        }
        sheet("my-trains-circular", circles, WidgetFixtures.lockCircular, columns: 4, style, cellWidth: 96, testName: testName, line: line)
        let lines = entries.map { name, entry in
            Cell(id: name) { LockInlineView(content: LockInlineContent(entry)).frame(width: 280, alignment: .leading) }
        }
        sheet("my-trains-inline", lines, CGSize(width: 280, height: 24), columns: 1, style, testName: testName, line: line)
    }

    // MARK: - Drawing

    private struct Cell: Identifiable {
        let id: String
        let view: AnyView

        @MainActor
        init(id: String, @ViewBuilder view: () -> some View) {
            self.id = id
            self.view = AnyView(view())
        }
    }

    /// The states in a grid, each at the widget's size under its name, on the stand-in wallpaper.
    @MainActor
    private func sheet(
        _ name: String, _ cells: [Cell], _ size: CGSize, columns: Int, _ style: UIUserInterfaceStyle, cellWidth: CGFloat? = nil,
        testName: String, line: UInt
    ) {
        let cellWidth = cellWidth ?? size.width
        let rows = stride(from: 0, to: cells.count, by: columns).map { Array(cells[$0..<min($0 + columns, cells.count)]) }
        let width = 32 + CGFloat(columns) * cellWidth + CGFloat(columns - 1) * 8
        let height = 32 + CGFloat(rows.count) * (18 + size.height) + CGFloat(rows.count - 1) * 12
        let wallpaper = style == .dark ? Color(red: 0.08, green: 0.11, blue: 0.17) : Color(white: 0.9)
        let view = VStack(alignment: .leading, spacing: 12) {
            ForEach(rows.indices, id: \.self) { row in
                HStack(alignment: .top, spacing: 8) {
                    ForEach(rows[row]) { cell in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: cell.id)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .frame(height: 14)
                            cell.view
                                .frame(width: size.width, height: size.height)
                        }
                        .frame(width: cellWidth, alignment: .leading)
                    }
                }
            }
        }
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(.primary)
        .padding(16)
        .frame(width: width, height: height, alignment: .topLeading)
        .background(wallpaper)
        let traits = ViewImageConfig.iPhone17Pro.traits.modifyingTraits { $0.userInterfaceStyle = style }
        let failure = verifySnapshot(
            of: view,
            as: .image(perceptualPrecision: 0.98, layout: .fixed(width: width, height: height), traits: traits),
            named: name,
            file: #filePath,
            testName: testName,
            line: line
        )
        if let failure {
            XCTFail("\(name): " + failure.replacingOccurrences(of: "\n", with: " | "), line: line)
        }
    }
}
