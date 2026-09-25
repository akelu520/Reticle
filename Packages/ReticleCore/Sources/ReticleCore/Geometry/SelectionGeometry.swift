import CoreGraphics

/// Resize handles around a selection rectangle.
public enum SelectionHandle: CaseIterable, Sendable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
}

/// Pure geometry for the capture selection. All coordinates are in a flipped
/// space (origin top-left, y grows downward), matching the overlay views.
public enum SelectionGeometry {
    /// Distance in points within which a handle or edge is considered hit.
    public static let hitTolerance: CGFloat = 6
    public static let toolbarGap: CGFloat = 8

    /// Rectangle spanned by a drag, normalized and clamped to `bounds`.
    public static func rect(from start: CGPoint, to end: CGPoint, within bounds: CGRect) -> CGRect {
        let a = clamp(start, to: bounds)
        let b = clamp(end, to: bounds)
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    /// Anchor points for each handle, used for drawing.
    public static func handlePoints(for rect: CGRect) -> [SelectionHandle: CGPoint] {
        [
            .topLeft: CGPoint(x: rect.minX, y: rect.minY),
            .top: CGPoint(x: rect.midX, y: rect.minY),
            .topRight: CGPoint(x: rect.maxX, y: rect.minY),
            .right: CGPoint(x: rect.maxX, y: rect.midY),
            .bottomRight: CGPoint(x: rect.maxX, y: rect.maxY),
            .bottom: CGPoint(x: rect.midX, y: rect.maxY),
            .bottomLeft: CGPoint(x: rect.minX, y: rect.maxY),
            .left: CGPoint(x: rect.minX, y: rect.midY),
        ]
    }

    /// Corners win over edges; edges are hit anywhere along their length.
    public static func handle(at p: CGPoint, in rect: CGRect, tolerance t: CGFloat = hitTolerance) -> SelectionHandle? {
        let corners: [SelectionHandle] = [.topLeft, .topRight, .bottomRight, .bottomLeft]
        let points = handlePoints(for: rect)
        for c in corners {
            let q = points[c]!
            if abs(p.x - q.x) <= t && abs(p.y - q.y) <= t { return c }
        }
        let withinX = p.x >= rect.minX - t && p.x <= rect.maxX + t
        let withinY = p.y >= rect.minY - t && p.y <= rect.maxY + t
        if withinX && abs(p.y - rect.minY) <= t { return .top }
        if withinX && abs(p.y - rect.maxY) <= t { return .bottom }
        if withinY && abs(p.x - rect.minX) <= t { return .left }
        if withinY && abs(p.x - rect.maxX) <= t { return .right }
        return nil
    }

    /// Moves the dragged handle to `p`; the opposite side stays fixed. Dragging
    /// past the opposite side flips the rectangle.
    public static func resize(_ rect: CGRect, handle: SelectionHandle, to p: CGPoint, within bounds: CGRect) -> CGRect {
        let p = clamp(p, to: bounds)
        var minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
        switch handle {
        case .topLeft: minX = p.x; minY = p.y
        case .top: minY = p.y
        case .topRight: maxX = p.x; minY = p.y
        case .right: maxX = p.x
        case .bottomRight: maxX = p.x; maxY = p.y
        case .bottom: maxY = p.y
        case .bottomLeft: minX = p.x; maxY = p.y
        case .left: minX = p.x
        }
        return CGRect(x: min(minX, maxX), y: min(minY, maxY), width: abs(maxX - minX), height: abs(maxY - minY))
    }

    /// Translates `rect`, keeping it fully inside `bounds`.
    public static func move(_ rect: CGRect, by d: CGVector, within bounds: CGRect) -> CGRect {
        var r = rect.offsetBy(dx: d.dx, dy: d.dy)
        r.origin.x = min(max(r.minX, bounds.minX), bounds.maxX - r.width)
        r.origin.y = min(max(r.minY, bounds.minY), bounds.maxY - r.height)
        return r
    }

    /// Toolbar goes right-aligned below the selection; if it does not fit,
    /// above; otherwise inside the selection's bottom-right corner.
    public static func toolbarOrigin(for sel: CGRect, toolbar size: CGSize, within bounds: CGRect) -> CGPoint {
        let g = toolbarGap
        let x = min(max(sel.maxX - size.width, bounds.minX), bounds.maxX - size.width)
        if sel.maxY + g + size.height <= bounds.maxY {
            return CGPoint(x: x, y: sel.maxY + g)
        }
        if sel.minY - g - size.height >= bounds.minY {
            return CGPoint(x: x, y: sel.minY - g - size.height)
        }
        return CGPoint(x: min(max(sel.maxX - size.width - g, bounds.minX), bounds.maxX - size.width),
                       y: max(sel.maxY - size.height - g, bounds.minY))
    }

    static func clamp(_ p: CGPoint, to b: CGRect) -> CGPoint {
        CGPoint(x: min(max(p.x, b.minX), b.maxX), y: min(max(p.y, b.minY), b.maxY))
    }
}
