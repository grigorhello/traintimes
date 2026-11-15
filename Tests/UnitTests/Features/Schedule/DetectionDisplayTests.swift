import XCTest
@testable import TrainTimes

/// Train detection's question as Schedule words it (TT-175; cut down by TT-205, D92: one line naming the rider's stop, Yes
/// and No, no checking strip).
final class DetectionDisplayTests: XCTestCase {
    func testTheQuestionNamesTheTrainsLastStop() throws {
        let question = try XCTUnwrap(TrainQuestion(DetectionFixtures.question()))
        XCTAssertEqual(question.title, "On the train to Clarkson?")
        XCTAssertEqual(question.train, DetectionFixtures.train)
    }

    func testTwoFittingTrainsAskAboutTheFirst() throws {
        let question = try XCTUnwrap(TrainQuestion(DetectionFixtures.question(both: true)))
        XCTAssertEqual(question.title, "On the train to Clarkson?")
        XCTAssertEqual(question.train, DetectionFixtures.train, "Yes starts the matcher's first candidate")
    }

    func testShortNamesDropGOAndStation() {
        XCTAssertEqual(TrainQuestion.shortName("Union Station GO"), "Union")
        XCTAssertEqual(TrainQuestion.shortName("Clarkson GO"), "Clarkson")
    }

    // MARK: What the strip under the day strip shows

    func testRideStripContentFollowsTheRideAndTheQuestion() {
        let checking = TrainMatcher.State.checking(DetectionFixtures.progress(stops: 1))
        let asking = TrainMatcher.State.asking(DetectionFixtures.question())
        XCTAssertEqual(RideStripContent(isRiding: false, detection: .idle), .otherwise)
        XCTAssertEqual(RideStripContent(isRiding: false, detection: checking), .otherwise, "no checking strip (D92)")
        XCTAssertEqual(RideStripContent(isRiding: false, detection: asking), .asking)
        // A ride wins over a question left up.
        XCTAssertEqual(RideStripContent(isRiding: true, detection: asking), .riding)
    }
}
