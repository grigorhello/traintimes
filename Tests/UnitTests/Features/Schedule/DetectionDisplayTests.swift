import XCTest
@testable import TrainTimes

/// The departure question's words on Schedule (TT-231; train detection's question that shared them went with TT-243, D120)
/// and what the strip under the day strip shows, in order.
@MainActor
final class DetectionDisplayTests: XCTestCase {
    func testTheQuestionNamesTheRidersStop() {
        XCTAssertEqual(TrainQuestionCard.title(stop: "Clarkson GO"), "On the train to Clarkson?")
    }

    func testShortNamesDropGOAndStation() {
        XCTAssertEqual(TrainQuestionCard.shortName("Union Station GO"), "Union")
        XCTAssertEqual(TrainQuestionCard.shortName("Clarkson GO"), "Clarkson")
    }

    // MARK: What the strip under the day strip shows

    /// Riding, the departure question, the automatic ride's strip, Automatic direction's strip, otherwise (TT-243).
    func testRideStripContentKeepsItsOrder() {
        XCTAssertEqual(RideStripContent(isRiding: false), .otherwise)
        XCTAssertEqual(RideStripContent(isRiding: false, showsDirectionStrip: true), .direction)
        XCTAssertEqual(RideStripContent(isRiding: false, showsAutoRideStrip: true, showsDirectionStrip: true), .autoRide)
        XCTAssertEqual(RideStripContent(isRiding: false, asksDeparture: true, showsAutoRideStrip: true), .asking)
        XCTAssertEqual(
            RideStripContent(isRiding: true, asksDeparture: true, showsAutoRideStrip: true, showsDirectionStrip: true), .riding
        )
    }
}
