import XCTest
@testable import TrainTimes

/// The strings and fixtures from the design handoff ship where the app and the tests read them (TT-101).
final class ResourcesTests: XCTestCase {
    /// Unit tests run inside the app, so `Bundle.main` is the app bundle.
    private var appBundle: Bundle { Bundle.main }
    private var testBundle: Bundle { Bundle(for: ResourcesTests.self) }

    func testLocalizableStringsShipInEnglishCanada() throws {
        let url = try XCTUnwrap(
            appBundle.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: "en-CA"),
            "en-CA.lproj/Localizable.strings is missing from the app bundle"
        )
        let table = try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String])
        XCTAssertGreaterThanOrEqual(table.count, 70, "Every string from design/handoff/Localizable.strings should be bundled")
        XCTAssertEqual(table["app.name"], "Train Times")
    }

    func testLocalizedLookupResolvesKeys() {
        XCTAssertEqual(appBundle.localizedString(forKey: "tab.schedule", value: nil, table: nil), "Schedule")
        XCTAssertEqual(appBundle.localizedString(forKey: "status.scheduled", value: nil, table: nil), "Scheduled")
        XCTAssertEqual(appBundle.developmentLocalization, "en-CA")
    }

    func testDisplayNameIsTrainTimes() {
        XCTAssertEqual(appBundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, "Train Times")
    }

    func testCopyHasNoExclamationMarks() throws {
        let url = try XCTUnwrap(appBundle.url(forResource: "Localizable", withExtension: "strings"))
        let table = try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String])
        let offending = table.filter { $0.value.contains("!") }.map(\.key).sorted()
        XCTAssertEqual(offending, [], "Copy rule D19: no exclamation marks")
    }

    func testFixturesLoadFromTestBundle() throws {
        let url = try XCTUnwrap(
            testBundle.url(forResource: "Fixtures", withExtension: "json"),
            "Fixtures.json is missing from the unit test bundle"
        )
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        let fixtures = try XCTUnwrap(object as? [String: Any])

        let route = try XCTUnwrap(fixtures["route"] as? [String: Any])
        let from = try XCTUnwrap(route["from"] as? [String: Any])
        let to = try XCTUnwrap(route["to"] as? [String: Any])
        XCTAssertEqual(from["name"] as? String, "Oakville")
        XCTAssertEqual(to["name"] as? String, "Union")
        XCTAssertEqual(fixtures["serviceDate"] as? String, "2026-11-05")

        let trains = try XCTUnwrap(fixtures["trains"] as? [[String: Any]])
        XCTAssertFalse(trains.isEmpty)
        for key in ["delayedScenario", "cancelledScenario", "eveningDark", "alerts"] {
            XCTAssertNotNil(fixtures[key], "Fixtures.json should carry \(key)")
        }
    }
}
