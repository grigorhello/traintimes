import UIKit
import XCTest
@testable import TrainTimes

/// The app icon and the in-app brand glyph ship in the app bundle (TT-103).
final class BrandAssetsTests: XCTestCase {
    func testAppIconIsCompiledIntoTheBundle() throws {
        let icons = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any])
        let primary = try XCTUnwrap(icons["CFBundlePrimaryIcon"] as? [String: Any])
        XCTAssertEqual(primary["CFBundleIconName"] as? String, "AppIcon")
    }

    @MainActor
    func testSymbolIsATemplateImage() throws {
        let symbol = try XCTUnwrap(UIImage(named: "TrainTimesSymbol"), "TrainTimesSymbol is missing from the asset catalog")
        XCTAssertEqual(symbol.renderingMode, .alwaysTemplate)
    }
}
