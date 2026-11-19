import XCTest
@testable import TrainTimes

/// Automatic direction's capsule (TT-234, D116): its three lines and their actions, and its small model, which shows a
/// capsule, hides it after its time and holds it while a finger is on it.
@MainActor
final class DirectionCapsuleTests: XCTestCase {
    /// A time no test waits for.
    private let never = Duration.seconds(300)
    private let short = Duration.milliseconds(60)

    private func eventually(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<500 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out", file: file, line: line)
    }

    /// Several times the short duration: a timer that was going to fire has fired.
    private func pause() async {
        try? await Task.sleep(for: .milliseconds(300))
    }

    // MARK: The lines

    /// "Now from Union" with Undo.
    func testTheTurnedCapsule() {
        let capsule = DirectionCapsule(id: 1, kind: .turned(station: "Union"))
        XCTAssertEqual(capsule.line.before, "Now from ")
        XCTAssertEqual(capsule.line.name, "Union")
        XCTAssertEqual(capsule.line.after, "")
        XCTAssertEqual(capsule.words, "Now from Union")
        XCTAssertEqual(capsule.actionKey, "button.undo")
        XCTAssertTrue(capsule.hasAction)
    }

    /// "Trains from Union?" with Switch: the question mark is apart from the name, so it shows when the name is cut.
    func testTheAskingCapsule() {
        let capsule = DirectionCapsule(id: 1, kind: .asks(station: "Union"))
        XCTAssertEqual(capsule.line.before, "Trains from ")
        XCTAssertEqual(capsule.line.name, "Union")
        XCTAssertEqual(capsule.line.after, "?")
        XCTAssertEqual(capsule.words, "Trains from Union?")
        XCTAssertEqual(capsule.actionKey, "direction.capsule.switch")
        XCTAssertTrue(capsule.hasAction)
    }

    /// "Won’t switch by itself for an hour", with no name and no action.
    func testTheCapsuleAfterUndo() {
        let capsule = DirectionCapsule(id: 1, kind: .kept)
        XCTAssertEqual(capsule.line.before, "Won’t switch by itself for an hour")
        XCTAssertEqual(capsule.line.name, "")
        XCTAssertEqual(capsule.line.after, "")
        XCTAssertEqual(capsule.words, "Won’t switch by itself for an hour")
        XCTAssertNil(capsule.actionKey)
        XCTAssertFalse(capsule.hasAction)
    }

    /// A long name is the only part that may be cut: the words around it stay whole.
    func testALongNameKeepsTheWordsAroundIt() {
        let name = "Brampton Innovation District"
        let asks = DirectionCapsule(id: 1, kind: .asks(station: name))
        XCTAssertEqual(asks.line.before, "Trains from ")
        XCTAssertEqual(asks.line.name, name)
        XCTAssertEqual(asks.line.after, "?")
        XCTAssertEqual(asks.words, "Trains from Brampton Innovation District?")

        let turned = DirectionCapsule(id: 2, kind: .turned(station: name))
        XCTAssertEqual(turned.line.before, "Now from ")
        XCTAssertEqual(turned.line.name, name)
        XCTAssertEqual(turned.words, "Now from Brampton Innovation District")
    }

    /// The action titles are in the strings file.
    func testTheActionsHaveTheirWords() {
        XCTAssertEqual(String(localized: "button.undo"), "Undo")
        XCTAssertEqual(String(localized: "direction.capsule.switch"), "Switch")
    }

    // MARK: The model

    func testShowsACapsule() {
        let model = DirectionCapsuleModel(actionDuration: never, plainDuration: never)
        XCTAssertNil(model.shown)

        model.show(.turned(station: "Union"))
        XCTAssertEqual(model.shown?.kind, .turned(station: "Union"))
        let first = model.shown?.id

        // Each capsule is a new one, also with the same words.
        model.show(.turned(station: "Union"))
        XCTAssertEqual(model.shown?.kind, .turned(station: "Union"))
        XCTAssertNotEqual(model.shown?.id, first)

        model.show(.kept)
        XCTAssertEqual(model.shown?.kind, .kept)
    }

    /// A capsule with an action hides after the action time.
    func testACapsuleWithAnActionHidesAfterItsTime() async {
        let model = DirectionCapsuleModel(actionDuration: short, plainDuration: never)
        let shown = ContinuousClock.now
        model.show(.asks(station: "Union"))
        XCTAssertNotNil(model.shown)

        await eventually { model.shown == nil }
        XCTAssertGreaterThanOrEqual(ContinuousClock.now - shown, short)

        // The line with no action has its own time.
        model.show(.kept)
        await pause()
        XCTAssertEqual(model.shown?.kind, .kept)
    }

    /// The line after Undo hides after the plain time.
    func testAPlainCapsuleHidesAfterItsTime() async {
        let model = DirectionCapsuleModel(actionDuration: never, plainDuration: short)
        let shown = ContinuousClock.now
        model.show(.kept)
        XCTAssertNotNil(model.shown)

        await eventually { model.shown == nil }
        XCTAssertGreaterThanOrEqual(ContinuousClock.now - shown, short)

        model.show(.turned(station: "Union"))
        await pause()
        XCTAssertEqual(model.shown?.kind, .turned(station: "Union"))
    }

    /// A finger on the capsule keeps it up, and lifting it starts the time again.
    func testAFingerHoldsTheCapsule() async {
        let model = DirectionCapsuleModel(actionDuration: short, plainDuration: short)
        model.show(.turned(station: "Union"))
        model.hold(true)
        await pause()
        XCTAssertEqual(model.shown?.kind, .turned(station: "Union"))

        let lifted = ContinuousClock.now
        model.hold(false)
        XCTAssertNotNil(model.shown)
        await eventually { model.shown == nil }
        XCTAssertGreaterThanOrEqual(ContinuousClock.now - lifted, short)
    }

    /// A newer capsule is not hidden by the older one's timer.
    func testANewerCapsuleOutlivesTheOlderOnesTimer() async {
        let model = DirectionCapsuleModel(actionDuration: short, plainDuration: never)
        model.show(.turned(station: "Union"))
        model.show(.kept)
        await pause()
        XCTAssertEqual(model.shown?.kind, .kept)

        // The same the other way round.
        let other = DirectionCapsuleModel(actionDuration: never, plainDuration: short)
        other.show(.kept)
        other.show(.asks(station: "Union"))
        await pause()
        XCTAssertEqual(other.shown?.kind, .asks(station: "Union"))
    }

    /// Dismissing ends the capsule at once, and its timer with it.
    func testDismissEndsTheCapsule() async {
        let model = DirectionCapsuleModel(actionDuration: short, plainDuration: never)
        model.dismiss()
        XCTAssertNil(model.shown)

        model.show(.turned(station: "Union"))
        model.dismiss()
        XCTAssertNil(model.shown)

        // The dismissed capsule's timer does not hide the next one.
        model.show(.kept)
        await pause()
        XCTAssertEqual(model.shown?.kind, .kept)
    }

    /// With nothing shown, a finger lifting starts no timer and shows nothing.
    func testAHoldWithNothingShownDoesNothing() async {
        let model = DirectionCapsuleModel(actionDuration: short, plainDuration: short)
        model.hold(true)
        model.hold(false)
        XCTAssertNil(model.shown)

        // A hold left over does not keep the next capsule up.
        model.hold(true)
        model.show(.asks(station: "Union"))
        await eventually { model.shown == nil }
    }
}
