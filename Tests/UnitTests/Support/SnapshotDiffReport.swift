import UIKit
import XCTest

/// Where a failed snapshot differs from its reference, written into the test log. Cloud sessions cannot download the CI
/// test results, so this is how they see a failure they cannot reproduce: the changed bands of rows, then a crop of the
/// new image around them as base64 PNG lines (`TTPNG i/n`).
@MainActor
enum SnapshotDiffReport {
    private struct Bitmap {
        let image: CGImage
        let width: Int
        let height: Int
        let pixels: [UInt8]
    }

    static func report(_ message: String, file: StaticString = #filePath, line: UInt = #line) {
        let urls = message.components(separatedBy: "\"").filter { $0.hasPrefix("file://") }.compactMap(URL.init(string:))
        guard urls.count >= 2, let reference = bitmap(urls[0]), let failed = bitmap(urls[1]),
              reference.width == failed.width, reference.height == failed.height else {
            XCTFail("TTDIFF no image pair: \(message.replacingOccurrences(of: "\n", with: " | "))", file: file, line: line)
            return
        }
        let width = failed.width
        var rows = [Int](repeating: 0, count: failed.height)
        var minX = width, maxX = -1
        for y in 0..<failed.height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                var delta = 0
                for c in 0..<3 { delta = max(delta, abs(Int(reference.pixels[i + c]) - Int(failed.pixels[i + c]))) }
                if delta > 8 {
                    rows[y] += 1
                    minX = min(minX, x)
                    maxX = max(maxX, x)
                }
            }
        }
        var bands: [(Int, Int, Int)] = []
        for (y, count) in rows.enumerated() where count > 0 {
            if let last = bands.last, y - last.1 <= 6 {
                bands[bands.count - 1] = (last.0, y, last.2 + count)
            } else {
                bands.append((y, y, count))
            }
        }
        let summary = bands.prefix(12).map { "y \($0.0)-\($0.1) n=\($0.2)" }.joined(separator: "; ")
        XCTFail("TTDIFF \(width)x\(failed.height) x \(minX)-\(maxX) bands: \(summary)", file: file, line: line)
        guard let top = bands.first?.0, let bottom = bands.last?.1, maxX >= minX else { return }

        let crop = CGRect(x: minX, y: top, width: maxX - minX + 1, height: bottom - top + 1).insetBy(dx: -24, dy: -24)
            .intersection(CGRect(x: 0, y: 0, width: width, height: failed.height))
        guard let cropped = failed.image.cropping(to: crop) else { return }
        let scale = min(1, 400 / crop.width)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: (crop.width * scale).rounded(), height: (crop.height * scale).rounded())
        let png = UIGraphicsImageRenderer(size: size, format: format).pngData { _ in
            UIImage(cgImage: cropped).draw(in: CGRect(origin: .zero, size: size))
        }
        let base64 = png.base64EncodedString()
        let chunks = stride(from: 0, to: base64.count, by: 3000).map { start -> String in
            let from = base64.index(base64.startIndex, offsetBy: start)
            let to = base64.index(from, offsetBy: min(3000, base64.count - start))
            return String(base64[from..<to])
        }
        XCTFail("TTPNG crop \(Int(crop.minX)),\(Int(crop.minY)) \(Int(crop.width))x\(Int(crop.height)) scale \(scale)", file: file, line: line)
        for (index, chunk) in chunks.enumerated() {
            XCTFail("TTPNG \(index + 1)/\(chunks.count) \(chunk)", file: file, line: line)
        }
    }

    private static func bitmap(_ url: URL) -> Bitmap? {
        guard let image = UIImage(contentsOfFile: url.path)?.cgImage else { return nil }
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? Bitmap(image: image, width: width, height: height, pixels: pixels) : nil
    }
}
