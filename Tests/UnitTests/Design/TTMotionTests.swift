import XCTest
@testable import TrainTimes

/// The Trip details staged entrance (TT-167, D65) as numbers, against the Motion board's Trip details row.
final class TTMotionTests: XCTestCase {
    /// The stop rows start 24 ms apart, and from the ninth row on together with the eighth (row 8 after the first).
    func testStopDelayStepsThenCapsAtTheEighthRow() {
        XCTAssertEqual(TTMotion.stopDelay(0), 0)
        XCTAssertEqual(TTMotion.stopDelay(1), 0.024, accuracy: 1e-9)
        XCTAssertEqual(TTMotion.stopDelay(7), 0.168, accuracy: 1e-9)
        XCTAssertEqual(TTMotion.stopDelay(8), 0.192, accuracy: 1e-9)
        XCTAssertEqual(TTMotion.stopDelay(9), 0.192, accuracy: 1e-9)
        XCTAssertEqual(TTMotion.stopDelay(40), 0.192, accuracy: 1e-9)
    }

    /// Still by about 0.7 s: the last row and the button are within 1 % of rest by then.
    func testEntranceSettlesByAboutSevenTenths() {
        XCTAssertEqual(TTMotion.stopsCurve.progress(at: 0.7 - TTMotion.stopDelay(8)), 1, accuracy: 0.01)
        XCTAssertEqual(TTMotion.growCurve.progress(at: 0.7 - TTMotion.buttonDelay), 1, accuracy: 0.01)
        XCTAssertEqual(TTMotion.cardCurve.progress(at: 0.7), 1, accuracy: 0.01)
    }
}
