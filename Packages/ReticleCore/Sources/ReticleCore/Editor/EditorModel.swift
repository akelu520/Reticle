import CoreGraphics
import Foundation

/// Annotation tools on the main toolbar.
public enum Tool: String, CaseIterable, Sendable {
    case rect, ellipse, arrow, pen, highlight, mosaic, text, label

    init(kind: AnnotationKind) {
        switch kind {
        case .rect: self = .rect
        case .ellipse: self = .ellipse
        case .arrow: self = .arrow
        case .pen: self = .pen
        case .highlight: self = .highlight
        case .mosaicBrush, .mosaicBox: self = .mosaic
        case .text: self = .text
        case .label: self = .label
        }
    }

    /// Whether the sub toolbar shows font sizes (text) instead of line widths.
    public var usesFontSize: Bool { self == .text || self == .label }
    /// Mosaic has no color.
    public var usesColor: Bool { self != .mosaic }
}

public enum MosaicMode: Equatable, Sendable { case brush, box }

public enum SizeLevel: Int, CaseIterable, Codable, Sendable { case small, medium, large }

public struct ToolPreset: Equatable, Sendable {
    public var color: RGBA
    public var size: SizeLevel
}

/// What the UI should do after a pointer-down.
public enum PointerOutcome: Equatable, Sendable {
    /// Nothing here; the caller may move the capture selection instead.
    case none
    case drawing
    case movingAnnotation
    case flippedLabel
    /// Show a text input with its top-left at this pixel point.
    case beginText(origin: CGPoint)
    /// Show a label input for a new label anchored here.
    case beginLabel(anchor: CGPoint)
    /// Show a text input prefilled with this annotation's text.
    case editText(UUID)
}

/// All annotation editing logic, free of UI. Points are image pixels.
public struct EditorModel {
    public let scale: CGFloat
    public private(set) var document = Document()
    public private(set) var selectedID: UUID?
    public private(set) var draft: Annotation?
    /// Annotation hidden from rendering while its text is edited in the UI.
    public private(set) var editingID: UUID?
    public var mosaicMode: MosaicMode = .brush

    public var tool: Tool? {
        didSet {
            if tool != nil { selectedID = nil }
        }
    }

    private enum PendingText {
        case newText(origin: CGPoint, style: Style)
        case newLabel(anchor: CGPoint, style: Style)
        case edit(UUID)
    }

    private var presets: [Tool: ToolPreset]
    private var history = History<Document>()
    private var pendingText: PendingText?
    private var move: (start: CGPoint, original: Annotation, before: Document, moved: Bool)?

    public init(scale: CGFloat) {
        self.scale = scale
        var p: [Tool: ToolPreset] = [:]
        for t in Tool.allCases { p[t] = ToolPreset(color: .red, size: .medium) }
        p[.highlight]?.color = .yellow
        presets = p
    }

    // MARK: - Styles

    public var canUndo: Bool { history.canUndo }
    public var canRedo: Bool { history.canRedo }

    /// The tool whose options the sub toolbar shows: the active tool, or the selected annotation's.
    public var styleTarget: Tool? {
        if let tool { return tool }
        return selectedID.flatMap { document.annotation($0) }.map { Tool(kind: $0.kind) }
    }

    public func preset(for tool: Tool) -> ToolPreset {
        presets[tool] ?? ToolPreset(color: .red, size: .medium)
    }

    /// Current options for the sub toolbar, reflecting the selected annotation if any.
    public var currentPreset: ToolPreset? {
        guard let target = styleTarget else { return nil }
        if tool == nil, let id = selectedID, let a = document.annotation(id) {
            return ToolPreset(color: a.style.color, size: sizeLevel(of: a))
        }
        return preset(for: target)
    }

    /// Line width in points for each tool and size level; multiplied by `scale`.
    public static func lineWidthPoints(_ tool: Tool, _ size: SizeLevel) -> CGFloat {
        switch tool {
        case .highlight: return [10, 16, 24][size.rawValue]
        case .mosaic: return [12, 20, 32][size.rawValue]
        default: return [2, 4, 8][size.rawValue]
        }
    }

    /// Font size in points (小/中/大).
    public static func fontSizePoints(_ size: SizeLevel) -> CGFloat {
        [14, 18, 24][size.rawValue]
    }

    func style(for tool: Tool) -> Style {
        let p = preset(for: tool)
        return Style(color: p.color,
                     lineWidth: Self.lineWidthPoints(tool, p.size) * scale,
                     fontSize: Self.fontSizePoints(p.size) * scale)
    }

    private func sizeLevel(of a: Annotation) -> SizeLevel {
        let tool = Tool(kind: a.kind)
        return SizeLevel.allCases.min { l, r in
            let value = tool.usesFontSize ? a.style.fontSize : a.style.lineWidth
            let lv = (tool.usesFontSize ? Self.fontSizePoints(l) : Self.lineWidthPoints(tool, l)) * scale
            let rv = (tool.usesFontSize ? Self.fontSizePoints(r) : Self.lineWidthPoints(tool, r)) * scale
            return abs(lv - value) < abs(rv - value)
        } ?? .medium
    }

    public mutating func setColor(_ color: RGBA) {
        guard let target = styleTarget else { return }
        presets[target]?.color = color
        updateSelected { $0.style.color = color }
    }

    public mutating func setSize(_ size: SizeLevel) {
        guard let target = styleTarget else { return }
        presets[target]?.size = size
        let fontSize = Self.fontSizePoints(size) * scale
        let lineWidth = Self.lineWidthPoints(target, size) * scale
        updateSelected { a in
            if target.usesFontSize {
                a.style.fontSize = fontSize
            } else {
                a.style.lineWidth = lineWidth
            }
        }
    }

    private mutating func updateSelected(_ change: (inout Annotation) -> Void) {
        guard tool == nil, let id = selectedID, let i = document.annotations.firstIndex(where: { $0.id == id }) else { return }
        var a = document.annotations[i]
        change(&a)
        guard a != document.annotations[i] else { return }
        history.record(document)
        document.annotations[i] = a
    }

    // MARK: - Pointer

    private var tolerance: CGFloat { 4 * scale }

    public mutating func pointerDown(at p: CGPoint, clickCount: Int = 1) -> PointerOutcome {
        let hit = document.hit(p, tolerance: tolerance)

        if clickCount >= 2, let hit, hit.kind.isTextual {
            return beginEditing(hit.id)
        }

        switch tool {
        case nil:
            guard let hit else {
                selectedID = nil
                return .none
            }
            selectedID = hit.id
            move = (p, hit, document, false)
            return .movingAnnotation

        case .text:
            if let hit, hit.kind == .text { return beginEditing(hit.id) }
            pendingText = .newText(origin: p, style: style(for: .text))
            return .beginText(origin: p)

        case .label:
            if let label = document.annotations.last(where: { $0.kind == .label && LabelLayout(annotation: $0).dot.insetBy(dx: -tolerance, dy: -tolerance).contains(p) }) {
                history.record(document)
                if let i = document.annotations.firstIndex(where: { $0.id == label.id }) {
                    document.annotations[i].labelFlipped.toggle()
                }
                return .flippedLabel
            }
            if let hit, hit.kind == .label { return beginEditing(hit.id) }
            pendingText = .newLabel(anchor: p, style: style(for: .label))
            return .beginLabel(anchor: p)

        case let tool?:
            let kind: AnnotationKind
            switch tool {
            case .rect: kind = .rect
            case .ellipse: kind = .ellipse
            case .arrow: kind = .arrow
            case .pen: kind = .pen
            case .highlight: kind = .highlight
            case .mosaic: kind = mosaicMode == .brush ? .mosaicBrush : .mosaicBox
            case .text, .label: return .none
            }
            draft = Annotation(kind: kind, points: kind.isStroke ? [p] : [p, p], style: style(for: tool))
            return .drawing
        }
    }

    public mutating func pointerDragged(to p: CGPoint, constrain: Bool = false) {
        if let m = move {
            let d = CGVector(dx: p.x - m.start.x, dy: p.y - m.start.y)
            if let i = document.annotations.firstIndex(where: { $0.id == m.original.id }) {
                document.annotations[i] = m.original.translated(by: d)
            }
            if hypot(d.dx, d.dy) > 0 { move?.moved = true }
            return
        }
        guard var d = draft, let start = d.points.first else { return }
        if d.kind.isStroke {
            if let last = d.points.last, hypot(p.x - last.x, p.y - last.y) >= max(scale, 1) {
                d.points.append(p)
            }
        } else {
            d.points = [start, constrain ? Self.constrained(from: start, to: p, kind: d.kind) : p]
        }
        draft = d
    }

    public mutating func pointerUp() {
        if let m = move {
            if m.moved { history.record(m.before) }
            move = nil
            return
        }
        guard var d = draft else { return }
        draft = nil
        if d.kind.isStroke {
            if d.points.count == 1 { d.points.append(d.points[0]) }
        } else {
            let r = d.spanRect
            let minSize = 2 * scale
            if d.kind == .arrow {
                guard hypot(r.width, r.height) >= minSize * 2 else { return }
            } else {
                guard r.width >= minSize, r.height >= minSize else { return }
            }
        }
        history.record(document)
        document.annotations.append(d)
    }

    static func constrained(from s: CGPoint, to p: CGPoint, kind: AnnotationKind) -> CGPoint {
        let dx = p.x - s.x, dy = p.y - s.y
        if kind == .arrow {
            let angle = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
            let len = hypot(dx, dy)
            return CGPoint(x: s.x + cos(angle) * len, y: s.y + sin(angle) * len)
        }
        let side = max(abs(dx), abs(dy))
        return CGPoint(x: s.x + (dx < 0 ? -side : side), y: s.y + (dy < 0 ? -side : side))
    }

    // MARK: - Text

    private mutating func beginEditing(_ id: UUID) -> PointerOutcome {
        pendingText = .edit(id)
        editingID = id
        selectedID = nil
        return .editText(id)
    }

    /// Commits the text input that was started by `.beginText`, `.beginLabel` or `.editText`.
    public mutating func finishText(_ text: String) {
        defer {
            pendingText = nil
            editingID = nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch pendingText {
        case let .newText(origin, style)?:
            guard !trimmed.isEmpty else { return }
            history.record(document)
            document.annotations.append(Annotation(kind: .text, points: [origin], style: style, text: text))
        case let .newLabel(anchor, style)?:
            guard !trimmed.isEmpty else { return }
            history.record(document)
            document.annotations.append(Annotation(kind: .label, points: [anchor], style: style, text: text))
        case let .edit(id)?:
            guard let i = document.annotations.firstIndex(where: { $0.id == id }) else { return }
            if trimmed.isEmpty {
                history.record(document)
                document.annotations.remove(at: i)
            } else if document.annotations[i].text != text {
                history.record(document)
                document.annotations[i].text = text
            }
        case nil:
            return
        }
    }

    public var isEditingText: Bool { pendingText != nil }

    /// Style of the text being edited, for configuring the UI input.
    public var pendingTextStyle: Style? {
        switch pendingText {
        case let .newText(_, style)?, let .newLabel(_, style)?: return style
        case let .edit(id)?: return document.annotation(id)?.style
        case nil: return nil
        }
    }

    // MARK: - Commands

    @discardableResult
    public mutating func deleteSelected() -> Bool {
        guard let id = selectedID, let i = document.annotations.firstIndex(where: { $0.id == id }) else { return false }
        history.record(document)
        document.annotations.remove(at: i)
        selectedID = nil
        return true
    }

    public mutating func undo() {
        guard let previous = history.undo(from: document) else { return }
        document = previous
        clearTransient()
    }

    public mutating func redo() {
        guard let next = history.redo(from: document) else { return }
        document = next
        clearTransient()
    }

    public mutating func setWatermark(_ w: Watermark?) {
        let value = (w?.text.isEmpty ?? true) ? nil : w
        guard value != document.watermark else { return }
        history.record(document)
        document.watermark = value
    }

    private mutating func clearTransient() {
        if let id = selectedID, document.annotation(id) == nil { selectedID = nil }
        draft = nil
        move = nil
    }

    /// Annotations to draw right now: the document without the one being edited, plus the draft.
    public var visibleAnnotations: [Annotation] {
        var list = document.annotations.filter { $0.id != editingID }
        if let draft { list.append(draft) }
        return list
    }
}
