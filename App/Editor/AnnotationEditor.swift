import AppKit
import ReticleCore

/// Annotation editing that can live in any flipped host view whose points map
/// to image pixels by `scale` (the capture overlay, or the long-screenshot
/// window). Owns the model, canvas, inline text input, sub toolbar and watermark panel.
@MainActor
final class AnnotationEditor {
    enum PointerResult {
        /// Not an editing gesture; the host may handle it (e.g. move the selection).
        case notHandled
        /// A drag that must be forwarded with `pointerDragged` / `pointerUp`.
        case dragging
        /// Fully handled by the editor.
        case handled
    }

    let scale: CGFloat
    let canvas: AnnotationCanvasView
    private let baseImage: CGImage
    private unowned let host: NSView
    private(set) var model: EditorModel
    private var pixelated: CGImage?
    private var textInput: TextInputView?
    /// Watermark edits are previewed on the canvas while the panel is open, then recorded as one undo step.
    private(set) var watermarkPanelOpen = false

    /// Called after any change, so the host can refresh its toolbar and panel layout.
    var onChange: (() -> Void)?

    private(set) lazy var subToolbar = SubToolbar(actions: .init(
        setSize: { [weak self] in self?.model.setSize($0); self?.refresh() },
        setColor: { [weak self] in self?.model.setColor($0); self?.refresh() },
        setMosaicMode: { [weak self] in self?.model.mosaicMode = $0; self?.refresh() }))
    private(set) lazy var watermarkPanel = WatermarkPanel(
        onChange: { [weak self] in self?.previewWatermark($0) },
        onDone: { [weak self] in self?.closeWatermarkPanel() })

    init(host: NSView, baseImage: CGImage, scale: CGFloat) {
        self.host = host
        self.baseImage = baseImage
        self.scale = scale
        self.model = EditorModel(scale: scale)
        self.canvas = AnnotationCanvasView(baseSize: CGSize(width: baseImage.width, height: baseImage.height), scale: scale)
    }

    var tool: Tool? { model.tool }
    var canUndo: Bool { model.canUndo }
    var watermarkActive: Bool { watermarkPanelOpen || model.document.watermark != nil }

    /// Drops every annotation, e.g. when the selection is discarded.
    func reset() {
        closeWatermarkPanel()
        commitTextInput()
        model = EditorModel(scale: scale)
        refresh()
    }

    /// The base image cropped to `pixelRect` with annotations burned in.
    func render(crop pixelRect: CGRect) -> CGImage? {
        commitTextInput()
        return Compositor.render(base: baseImage, pixelated: pixelated, document: model.document, crop: pixelRect)
    }

    // MARK: - Commands

    func toggleTool(_ tool: Tool) {
        commitTextInput()
        closeWatermarkPanel()
        model.tool = model.tool == tool ? nil : tool
        if model.tool == .mosaic, pixelated == nil {
            pixelated = Mosaic.pixelate(baseImage, blockSize: 12 * scale)
            canvas.pixelated = pixelated
        }
        refresh()
        host.window?.makeFirstResponder(host)
    }

    func undo() {
        commitTextInput()
        model.undo()
        refresh()
    }

    /// ⌘Z, ⇧⌘Z and Delete. Returns true when the key was consumed.
    func handleKey(_ event: NSEvent) -> Bool {
        let cmd = event.modifierFlags.contains(.command)
        switch Int(event.keyCode) {
        case 6 where cmd: // Z
            if event.modifierFlags.contains(.shift) { model.redo() } else { model.undo() }
            refresh()
            return true
        case 51, 117: // Delete, Forward Delete
            if model.deleteSelected() { refresh() }
            return true
        default:
            return false
        }
    }

    // MARK: - Pointer (host points)

    func pointerDown(at p: CGPoint, clickCount: Int) -> PointerResult {
        commitTextInput()
        closeWatermarkPanel()
        defer { refresh() }
        switch model.pointerDown(at: pixel(p), clickCount: clickCount) {
        case .none:
            return .notHandled
        case .drawing, .movingAnnotation:
            return .dragging
        case .flippedLabel:
            return .handled
        case let .beginText(origin):
            beginTextInput(kind: .text, origin: origin, text: "")
        case let .beginLabel(anchor):
            beginTextInput(kind: .label, origin: anchor, text: "")
        case let .editText(id):
            if let a = model.document.annotation(id) {
                beginTextInput(kind: a.kind, origin: a.points.first ?? .zero, text: a.text, flipped: a.labelFlipped)
            }
        }
        return .handled
    }

    func pointerDragged(to p: CGPoint, constrain: Bool) {
        model.pointerDragged(to: pixel(p), constrain: constrain)
        refreshCanvas()
    }

    func pointerUp() {
        model.pointerUp()
        refresh()
    }

    /// Cursor inside the editable area.
    func cursor(at p: CGPoint) -> NSCursor {
        switch model.tool {
        case .text?: return .iBeam
        case .some: return .crosshair
        case nil: return model.document.hit(pixel(p), tolerance: 4 * scale) != nil ? .pointingHand : .openHand
        }
    }

    private func pixel(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x * scale, y: p.y * scale)
    }

    // MARK: - Text input

    private func beginTextInput(kind: AnnotationKind, origin: CGPoint, text: String, flipped: Bool = false) {
        guard let style = model.pendingTextStyle else { return }
        let isLabel = kind == .label
        let input = TextInputView(fontSize: style.fontSize / scale,
                                  color: isLabel ? (style.color.isLight ? RGBA.black : RGBA.white).nsColor : style.color.nsColor,
                                  bubble: isLabel ? style.color.nsColor : nil)
        input.string = text
        let scale = self.scale
        let place: (String) -> Void = { [weak input] current in
            guard let input else { return }
            let size = TextMetrics.size(of: current, fontSize: style.fontSize)
            let originPx = isLabel
                ? LabelLayout(anchor: origin, text: current, fontSize: style.fontSize, flipped: flipped).textOrigin
                : origin
            input.frame = CGRect(x: originPx.x / scale, y: originPx.y / scale,
                                 width: max(size.width / scale, 12), height: size.height / scale)
        }
        input.onTextChange = place
        input.onFinish = { [weak self] in self?.commitTextInput() }
        place(text)
        host.addSubview(input)
        textInput = input
        host.window?.makeFirstResponder(input)
        input.selectAll(nil)
    }

    func commitTextInput() {
        guard let input = textInput else { return }
        textInput = nil
        model.finishText(input.string)
        input.removeFromSuperview()
        host.window?.makeFirstResponder(host)
        refresh()
    }

    // MARK: - Watermark

    func toggleWatermarkPanel() {
        if watermarkPanelOpen {
            closeWatermarkPanel()
            return
        }
        commitTextInput()
        model.tool = nil
        watermarkPanelOpen = true
        watermarkPanel.load(model.document.watermark)
        refresh()
        watermarkPanel.focus()
    }

    private func previewWatermark(_ v: WatermarkPanel.Value) {
        canvas.content.watermark = v.text.isEmpty ? nil
            : Watermark(text: v.text, opacity: v.opacity, color: v.color, fontSize: 18 * scale)
    }

    func closeWatermarkPanel() {
        guard watermarkPanelOpen else { return }
        watermarkPanelOpen = false
        model.setWatermark(canvas.content.watermark)
        host.window?.makeFirstResponder(host)
        refresh()
    }

    // MARK: - Panels and drawing

    /// The panel that belongs next to the main toolbar, configured and added to `parent`; nil if none.
    func secondaryPanel(in parent: NSView) -> FloatingPanelView? {
        let panel: FloatingPanelView?
        if watermarkPanelOpen {
            panel = watermarkPanel
            subToolbar.isHidden = true
        } else if let target = model.styleTarget, let preset = model.currentPreset {
            subToolbar.configure(tool: target, preset: preset, mosaicMode: model.mosaicMode)
            panel = subToolbar
            watermarkPanel.isHidden = true
        } else {
            panel = nil
            hideSecondaryPanels()
        }
        if let panel {
            if panel.superview !== parent { parent.addSubview(panel) }
            panel.isHidden = false
            panel.layoutSubtreeIfNeeded()
        }
        return panel
    }

    func hideSecondaryPanels() {
        subToolbar.isHidden = true
        watermarkPanel.isHidden = true
    }

    func refresh() {
        refreshCanvas()
        onChange?()
    }

    private func refreshCanvas() {
        let selected = model.tool == nil ? model.selectedID.flatMap { model.document.annotation($0) } : nil
        let watermark = watermarkPanelOpen ? canvas.content.watermark : model.document.watermark
        canvas.content = .init(annotations: model.visibleAnnotations, watermark: watermark, selectedBounds: selected?.bounds)
    }

    #if DEBUG
    /// Adds one of each annotation inside `rect` (host points) for visual checks.
    func debugPopulate(in rect: CGRect) {
        let s = scale
        func px(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: (rect.minX + rect.width * x) * s, y: (rect.minY + rect.height * y) * s) }
        for (tool, a, b) in [(Tool.rect, px(0.05, 0.1), px(0.35, 0.45)), (.ellipse, px(0.4, 0.1), px(0.6, 0.45)), (.arrow, px(0.65, 0.4), px(0.95, 0.1))] {
            model.tool = tool
            _ = model.pointerDown(at: a); model.pointerDragged(to: b); model.pointerUp()
        }
        model.tool = .mosaic
        pixelated = Mosaic.pixelate(baseImage, blockSize: 12 * s)
        canvas.pixelated = pixelated
        model.mosaicMode = .box
        _ = model.pointerDown(at: px(0.05, 0.55)); model.pointerDragged(to: px(0.3, 0.95)); model.pointerUp()
        model.tool = .highlight
        _ = model.pointerDown(at: px(0.35, 0.7)); model.pointerDragged(to: px(0.5, 0.72)); model.pointerDragged(to: px(0.6, 0.7)); model.pointerUp()
        model.tool = .text
        _ = model.pointerDown(at: px(0.35, 0.52)); model.finishText("文本 Text")
        model.tool = .label
        _ = model.pointerDown(at: px(0.7, 0.75)); model.finishText("标签")
        model.setWatermark(Watermark(text: "Reticle", opacity: 0.25, color: .black, fontSize: 18 * s))
        model.tool = .rect
        refresh()
    }
    #endif
}
