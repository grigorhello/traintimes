import XCTest
@testable import TrainTimes

/// The widget extension ships inside the app with the app's version and the widget strings, and the App Group is reachable
/// (TT-181, D101).
final class WidgetExtensionTests: XCTestCase {
    private var appex: Bundle {
        get throws {
            let plugIns = try XCTUnwrap(Bundle.main.builtInPlugInsURL)
            let url = plugIns.appendingPathComponent("TrainTimesWidgets.appex")
            return try XCTUnwrap(Bundle(url: url), "TrainTimesWidgets.appex is missing from the app's PlugIns")
        }
    }

    func testExtensionIsEmbeddedWithTheAppsVersion() throws {
        let bundle = try appex
        XCTAssertEqual(bundle.bundleIdentifier, "ca.traintimes.TrainTimes.Widgets")
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        XCTAssertNotNil(version)
        XCTAssertEqual(version, Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        let extensionInfo = try XCTUnwrap(bundle.object(forInfoDictionaryKey: "NSExtension") as? [String: Any])
        XCTAssertEqual(extensionInfo["NSExtensionPointIdentifier"] as? String, "com.apple.widgetkit-extension")
    }

    func testExtensionReadsTheWidgetStrings() throws {
        let bundle = try appex
        let expected = [
            "widget.next.name": "Next train",
            "widget.next.description": "Your next saved train and how long until it leaves.",
            "widget.departures.name": "Departures",
            "widget.departures.description": "Your saved trains and when they arrive.",
            "widget.not_loaded.title": "Open Train Times once",
            "widget.not_loaded.body": "to load the timetable.",
            "widget.edit.title": "My trains",
            "widget.edit.show": "Show",
            "widget.edit.my_trains": "My trains",
            "widget.edit.a_route": "A route",
            "widget.edit.turn_around": "Turn around at 12 PM",
            "widget.edit.turn_around.description": "After 12 PM the widget shows the way back.",
        ]
        for (key, value) in expected {
            XCTAssertEqual(bundle.localizedString(forKey: key, value: nil, table: nil), value, key)
        }
    }

    func testAppGroupContainerIsReachable() {
        XCTAssertEqual(AppGroup.identifier, "group.ca.traintimes.TrainTimes")
        XCTAssertNotNil(AppGroup.containerURL)
    }
}
