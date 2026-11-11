import SwiftUI

/// The canvas's train front: a body with a window and two lamps cut out, and the rail under it, in a 100 unit box. Shared by
/// the app (the ride's stop list, TT-172) and the widget extension (the Live Activity's bar, TT-174).
struct TrainGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 100
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale)
        }
        func box(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
            CGRect(origin: point(x, y), size: CGSize(width: width * scale, height: height * scale))
        }
        var path = Path()
        path.addPath(
            Path(
                roundedRect: box(18, 18, 64, 62),
                cornerRadii: RectangleCornerRadii(
                    topLeading: 18 * scale, bottomLeading: 10 * scale, bottomTrailing: 10 * scale, topTrailing: 18 * scale
                )
            )
        )
        path.addPath(Path(roundedRect: box(28, 30, 44, 22), cornerRadius: 5 * scale))
        path.addEllipse(in: box(30, 60, 12, 12))
        path.addEllipse(in: box(58, 60, 12, 12))
        path.addPath(Path(roundedRect: box(24, 86, 52, 7), cornerRadius: 3.5 * scale))
        return path
    }
}
