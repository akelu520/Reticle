import CoreGraphics

/// Geometry shared by hit testing and rendering.
public enum ShapePaths {
    /// Filled arrow: a shaft that tapers toward the start, and a triangular head.
    public static func arrow(from start: CGPoint, to end: CGPoint, width w: CGFloat) -> CGPath {
        let dx = end.x - start.x, dy = end.y - start.y
        let length = hypot(dx, dy)
        let path = CGMutablePath()
        guard length > 0.5 else { return path }
        let ux = dx / length, uy = dy / length
        let nx = -uy, ny = ux
        let headLength = min(max(w * 4, 10), length)
        let headHalf = headLength * 0.45
        let base = CGPoint(x: end.x - ux * headLength, y: end.y - uy * headLength)
        func p(_ o: CGPoint, _ n: CGFloat) -> CGPoint { CGPoint(x: o.x + nx * n, y: o.y + ny * n) }
        path.addLines(between: [
            p(start, w * 0.15), p(base, w / 2), p(base, headHalf), end,
            p(base, -headHalf), p(base, -w / 2), p(start, -w * 0.15),
        ])
        path.closeSubpath()
        return path
    }

    /// Smoothed freehand path through the sampled points (quadratic curves via midpoints).
    public static func stroke(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        if points.count == 1 {
            path.addLine(to: first)
            return path
        }
        if points.count == 2 {
            path.addLine(to: points[1])
            return path
        }
        for i in 1..<(points.count - 1) {
            let mid = CGPoint(x: (points[i].x + points[i + 1].x) / 2, y: (points[i].y + points[i + 1].y) / 2)
            path.addQuadCurve(to: mid, control: points[i])
        }
        path.addLine(to: points[points.count - 1])
        return path
    }
}
