import SnapshotTesting
import SwiftUI
import XCTest
@testable import TrainTimes

/// TEMPORARY probe, not for merging: draws the permission sheet the way RideSnapshotTests does, many times in one run, and
/// reports the Continue button's colour and the captured image's format each time. testPermissionLight sometimes finds the
/// button in a second colour (0.9472656 of pixels match, ΔE at most 8.4), and the CI log cannot show the image.
final class RidePermissionProbeTests: XCTestCase {
    @MainActor
    func testProbeContinueButtonColour() throws {
        var lines: [String] = []
        for index in 0..<16 {
            // A dark sheet before some of the light ones, as testPermissionDark runs just before testPermissionLight.
            let style: UIUserInterfaceStyle = index % 4 == 2 ? .dark : .light
            let view = permission
                .environment(\.timeFormatter, TimeFormatter(format: .twelveHour))
                .environment(\.rendersGlass, false)
                .environment(\.playsRideMotion, false)
            layOutOnce(view)
            let image = try capture(view, style)
            lines.append(
                "\(index)\(style == .dark ? "D" : "L") button \(pixel(image, 120, 2001))/\(pixel(image, 1000, 2001))"
                    + " text \(pixel(image, 603, 2001)) tile \(pixel(image, 603, 930)) canvas \(pixel(image, 603, 2300))"
                    + " dim \(pixel(image, 603, 300)) \(image.width)x\(image.height) \(image.bitsPerComponent)b"
                    + " \(image.colorSpace?.name.map { $0 as String } ?? "?") info \(image.bitmapInfo.rawValue)"
            )
        }
        XCTFail("probe: " + lines.joined(separator: " | "))
    }

    @MainActor
    private func capture(_ view: some View, _ style: UIUserInterfaceStyle) throws -> CGImage {
        let strategy = Snapshotting<AnyView, UIImage>.image(
            drawHierarchyInKeyWindow: true,
            layout: .device(config: .iPhone17Pro),
            traits: UITraitCollection(userInterfaceStyle: style)
        )
        var captured: UIImage?
        let done = expectation(description: "capture")
        strategy.snapshot(AnyView(view)).run { image in
            captured = image
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
        return try XCTUnwrap(captured?.cgImage)
    }

    /// The pixel at (x, y) from the top left, as Display P3 bytes (the space the reference PNGs are saved in).
    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> String {
        guard let space = CGColorSpace(name: CGColorSpace.displayP3) else { return "?" }
        var bytes = [UInt8](repeating: 0, count: 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            // Core Graphics counts from the bottom: move the image so the asked pixel lands on the context's one pixel.
            context.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
            return true
        }
        return drawn ? "\(bytes[0]),\(bytes[1]),\(bytes[2])" : "?"
    }

    /// RideSnapshotTests' permission sheet over a dimmed Trip details.
    @MainActor
    private var permission: some View {
        ZStack(alignment: .bottom) {
            TTColor.canvas
            Color.black.opacity(0.2)
            RideIntroSheet(destination: "Clarkson")
                .frame(height: RideIntroSheet.height)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: TTRadius.sheet, topTrailingRadius: TTRadius.sheet))
        }
        .ignoresSafeArea()
    }
}
