import CoreGraphics
import Foundation

public enum AnnotationKind: String, Codable, CaseIterable, Sendable {
    case rect, ellipse, arrow, pen, highlight, mosaicBrush, mosaicBox, text, label

    /// Paint order: mosaic → highlight → shapes → text. Lower draws first.
    var layer: Int {
        switch self {
        case .mosaicBrush, .mosaicBox: return 0
        case .highlight: return 1
        case .rect, .ellipse, .arrow, .pen: return 2
        case .text, .label: return 3
        }
    }

    var isStroke: Bool {
        switch self {
        case .pen, .highlight, .mosaicBrush: return true
        default: return false
        }
    }

    var isTextual: Bool { self == .text || self == .label }
}

public struct Style: Codable, Equatable, Hashable, Sendable {
    public var color: RGBA
    /// Stroke width in image pixels.
    public var lineWidth: CGFloat
    /// Font size in image pixels.
    public var fontSize: CGFloat

    public init(color: RGBA, lineWidth: CGFloat, fontSize: CGFloat) {
        self.color = color
        self.lineWidth = lineWidth
        self.fontSize = fontSize
    }
}

/// One mark on the screenshot. Coordinates are image pixels, top-left origin.
public struct Annotation: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var kind: AnnotationKind
    /// Shapes: [start, end]. Strokes: sampled points. Text: [top-left]. Label: [anchor].
    public var points: [CGPoint]
    public var style: Style
    public var text: String
    /// Label only: bubble on the left of the anchor instead of the right.
    public var labelFlipped: Bool

    public init(id: UUID = UUID(), kind: AnnotationKind, points: [CGPoint], style: Style, text: String = "", labelFlipped: Bool = false) {
        self.id = id
        self.kind = kind
        self.points = points
        self.style = style
        self.text = text
        self.labelFlipped = labelFlipped
    }

    /// Rectangle spanned by the first and last point.
    public var spanRect: CGRect {
        guard let a = points.first, let b = points.last else { return .null }
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    public func translated(by d: CGVector) -> Annotation {
        var copy = self
        copy.points = points.map { CGPoint(x: $0.x + d.dx, y: $0.y + d.dy) }
        return copy
    }

    /// Bounds of the rendered mark, used for the selection outline.
    public var bounds: CGRect {
        switch kind {
        case .text:
            guard let o = points.first else { return .null }
            return CGRect(origin: o, size: TextMetrics.size(of: text, fontSize: style.fontSize))
        case .label:
            return LabelLayout(annotation: self).bounds
        case .arrow:
            return ShapePaths.arrow(from: points.first ?? .zero, to: points.last ?? .zero, width: style.lineWidth).boundingBoxOfPath
        default:
            let pad = style.lineWidth / 2
            let r = kind.isStroke ? ShapePaths.stroke(points).boundingBoxOfPath : spanRect
            return r.insetBy(dx: -pad, dy: -pad)
        }
    }

    /// Whether `p` touches this mark, with `tolerance` pixels of slack.
    public func hitTest(_ p: CGPoint, tolerance: CGFloat) -> Bool {
        switch kind {
        case .text, .label, .mosaicBox:
            return bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(p)
        case .arrow:
            let path = ShapePaths.arrow(from: points.first ?? .zero, to: points.last ?? .zero, width: style.lineWidth)
            return path.contains(p) || path.copy(strokingWithWidth: tolerance * 2, lineCap: .round, lineJoin: .round, miterLimit: 1).contains(p)
        case .rect, .ellipse, .pen, .highlight, .mosaicBrush:
            let path = kind == .rect ? CGPath(rect: spanRect, transform: nil)
                : kind == .ellipse ? CGPath(ellipseIn: spanRect, transform: nil)
                : ShapePaths.stroke(points)
            let width = max(style.lineWidth, 1) + tolerance * 2
            return path.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 1).contains(p)
        }
    }
}

public struct Watermark: Codable, Equatable, Sendable {
    public var text: String
    /// 0.1 ... 1.
    public var opacity: CGFloat
    public var color: RGBA
    /// Font size in image pixels.
    public var fontSize: CGFloat

    public init(text: String, opacity: CGFloat, color: RGBA, fontSize: CGFloat) {
        self.text = text
        self.opacity = opacity
        self.color = color
        self.fontSize = fontSize
    }
}

/// Everything the user added on top of the screenshot. Snapshots of this are the undo history.
public struct Document: Codable, Equatable, Sendable {
    public var annotations: [Annotation] = []
    public var watermark: Watermark?

    public init(annotations: [Annotation] = [], watermark: Watermark? = nil) {
        self.annotations = annotations
        self.watermark = watermark
    }

    public func annotation(_ id: UUID) -> Annotation? {
        annotations.first { $0.id == id }
    }

    /// Topmost annotation under `p`, respecting paint order.
    public func hit(_ p: CGPoint, tolerance: CGFloat) -> Annotation? {
        Self.paintOrder(annotations).reversed().first { $0.hitTest(p, tolerance: tolerance) }
    }

    /// Stable sort by paint layer, keeping insertion order within a layer.
    public static func paintOrder(_ list: [Annotation]) -> [Annotation] {
        list.enumerated().sorted { ($0.element.kind.layer, $0.offset) < ($1.element.kind.layer, $1.offset) }.map(\.element)
    }
}
