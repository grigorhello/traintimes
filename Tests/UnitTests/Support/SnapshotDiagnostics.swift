import SnapshotTesting
import SwiftUI
import UIKit
import XCTest

/// Where a failed device snapshot differs from its reference, on one line for the CI log: how many pixels, the box they sit
/// in, how they spread down the screen, and the most common reference → new colour pairs (Display P3 bytes). It also saves
/// the new image as `__Snapshots__/Diagnostics/<Suite>.<test>.png` beside the suite, which CI's recording step commits to a
/// pull request. Cloud sessions cannot download the TestResults artifact, so the log and that commit are all they can see.
@MainActor
func snapshotDiagnostics(
    of view: some View,
    style: UIUserInterfaceStyle,
    file: StaticString,
    testName: String
) -> String {
    let fileURL = URL(fileURLWithPath: "\(file)", isDirectory: false)
    let suite = fileURL.deletingPathExtension().lastPathComponent
    // The name swift-snapshot-testing gives the reference: "testPermissionLight()" → "testPermissionLight".
    let name = testName
        .replacingOccurrences(of: "\\W+", with: "-", options: .regularExpression)
        .replacingOccurrences(of: "^-|-$", with: "", options: .regularExpression)
    let snapshots = fileURL.deletingLastPathComponent().appendingPathComponent("__Snapshots__", isDirectory: true)
    guard let actual = captureDeviceImage(view, style: style) else { return "diagnostics: no image" }

    var notes: [String] = []
    let folder = snapshots.appendingPathComponent("Diagnostics", isDirectory: true)
    do {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try UIImage(cgImage: actual).pngData()?.write(to: folder.appendingPathComponent("\(suite).\(name).png"))
    } catch {
        notes.append("image not saved: \(error.localizedDescription)")
    }

    let referencePath = snapshots.appendingPathComponent(suite).appendingPathComponent("\(name).1.png").path
    guard let reference = UIImage(contentsOfFile: referencePath)?.cgImage else {
        return "diagnostics: no reference at \(referencePath)"
    }
    notes.append("new \(describe(actual)), reference \(describe(reference))")
    let width = reference.width
    let height = reference.height
    guard actual.width == width, actual.height == height else {
        return "diagnostics: size \(actual.width)x\(actual.height), reference \(width)x\(height); " + notes.joined(separator: "; ")
    }
    guard let old = displayP3Bytes(reference), let new = displayP3Bytes(actual) else {
        return "diagnostics: could not read the pixels; " + notes.joined(separator: "; ")
    }

    var count = 0
    var minX = width, maxX = -1, minY = height, maxY = -1
    var bands = [Int](repeating: 0, count: (height + 59) / 60)
    var pairs: [UInt64: Int] = [:]
    old.withUnsafeBufferPointer { a in
        new.withUnsafeBufferPointer { b in
            for y in 0..<height {
                for x in 0..<width {
                    let i = (y * width + x) * 4
                    let red = abs(Int(a[i]) - Int(b[i]))
                    let green = abs(Int(a[i + 1]) - Int(b[i + 1]))
                    let blue = abs(Int(a[i + 2]) - Int(b[i + 2]))
                    guard max(red, green, blue) > 2 else { continue }
                    count += 1
                    minX = min(minX, x)
                    maxX = max(maxX, x)
                    minY = min(minY, y)
                    maxY = max(maxY, y)
                    bands[y / 60] += 1
                    let was: UInt64 = (UInt64(a[i]) << 16) | (UInt64(a[i + 1]) << 8) | UInt64(a[i + 2])
                    let now: UInt64 = (UInt64(b[i]) << 16) | (UInt64(b[i + 1]) << 8) | UInt64(b[i + 2])
                    pairs[(was << 24) | now, default: 0] += 1
                }
            }
        }
    }
    guard count > 0 else { return "diagnostics: the new image matches the reference within 2/255; " + notes.joined(separator: "; ") }

    let share = Double(count) / Double(width * height) * 100
    let rows = bands.enumerated().filter { $0.element > 0 }.map { "\($0.offset * 60):\($0.element)" }.joined(separator: " ")
    let colours = pairs.sorted { $0.value > $1.value }.prefix(10).map { pair -> String in
        let shifts: [UInt64] = [40, 32, 24, 16, 8, 0]
        let c = shifts.map { (pair.key >> $0) & 0xFF }
        return "\(c[0]),\(c[1]),\(c[2])→\(c[3]),\(c[4]),\(c[5]) ×\(pair.value)"
    }.joined(separator: ", ")
    return "diagnostics: \(count) px (\(String(format: "%.2f", share))%) differ by more than 2/255 in x \(minX)–\(maxX),"
        + " y \(minY)–\(maxY) px; per 60 px row band [\(rows)]; \(pairs.count) colour pairs, most common [\(colours)]; "
        + notes.joined(separator: "; ")
}

/// The image the device snapshot strategy draws, as `verifySnapshot` takes it.
@MainActor
private func captureDeviceImage(_ view: some View, style: UIUserInterfaceStyle) -> CGImage? {
    let strategy = Snapshotting<AnyView, UIImage>.image(
        drawHierarchyInKeyWindow: true,
        layout: .device(config: .iPhone17Pro),
        traits: UITraitCollection(userInterfaceStyle: style)
    )
    var captured: UIImage?
    let done = XCTestExpectation(description: "capture")
    strategy.snapshot(AnyView(view)).run { image in
        captured = image
        done.fulfill()
    }
    _ = XCTWaiter().wait(for: [done], timeout: 10)
    return captured?.cgImage
}

/// The image's pixels as 8-bit Display P3 RGBA, top row first.
private func displayP3Bytes(_ image: CGImage) -> [UInt8]? {
    guard let space = CGColorSpace(name: CGColorSpace.displayP3) else { return nil }
    let width = image.width
    let height = image.height
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
        guard let context = CGContext(
            data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    return drawn ? bytes : nil
}

private func describe(_ image: CGImage) -> String {
    let space = image.colorSpace?.name.map { $0 as String } ?? "?"
    return "\(image.bitsPerComponent)b \(space) info \(image.bitmapInfo.rawValue)"
}
