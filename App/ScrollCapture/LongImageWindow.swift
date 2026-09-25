import AppKit
import ReticleCore

/// Result of a scroll capture. Bottom bar: 编辑 / 保存 /
/// 取消 / 保存到剪切板. 编辑 swaps in the annotation toolbar; the whole long
/// image is editable inside a scroll view.
@MainActor
final class LongImageWindow: NSWindow, NSWindowDelegate {
    private static var open: [LongImageWindow] = []

    private let image: CGImage
    private let scale: CGFloat
    private let document: LongImageDocumentView
    private let footer = NSView()
    private var resultBar: FloatingPanelView!
    private var editToolbar: CaptureToolbar!
    private static let footerHeight: CGFloat = 96

    static func show(image: CGImage, scale: CGFloat) {
        let w = LongImageWindow(image: image, scale: scale)
        open.append(w)
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    private init(image: CGImage, scale: CGFloat) {
        self.image = image
        self.scale = scale
        document = LongImageDocumentView(image: image, scale: scale)
        let visible = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let imageSize = document.frame.size
        let width = min(max(imageSize.width + 20, 640), visible.width * 0.9)
        let height = min(imageSize.height + Self.footerHeight, visible.height * 0.9)
        super.init(contentRect: CGRect(x: 0, y: 0, width: width, height: height),
                   styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        title = "滚动截图 · \(image.width) × \(image.height)"
        isReleasedWhenClosed = false
        delegate = self
        level = .floating
        center()
        buildContent()
    }

    private func buildContent() {
        guard let content = contentView else { return }
        let scroll = NSScrollView(frame: CGRect(x: 0, y: Self.footerHeight, width: content.bounds.width, height: content.bounds.height - Self.footerHeight))
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.backgroundColor = NSColor(white: 0.9, alpha: 1)
        scroll.documentView = document
        content.addSubview(scroll)

        footer.frame = CGRect(x: 0, y: 0, width: content.bounds.width, height: Self.footerHeight)
        footer.autoresizingMask = [.width]
        content.addSubview(footer)

        resultBar = FloatingPanelView(spacing: 4)
        for (symbol, tip, action) in [("pencil", "编辑", #selector(startEditing)), ("arrow.down.to.line", "保存", #selector(save)),
                                      ("xmark", "取消", #selector(cancel)), ("checkmark", "保存到剪切板", #selector(copyToPasteboard))] {
            let b = IconButton(symbol: symbol, tip: tip) { [weak self] in _ = self?.perform(action) }
            if action == #selector(copyToPasteboard) { b.baseTint = Palette.accent }
            resultBar.stack.addArrangedSubview(b)
        }
        footer.addSubview(resultBar)

        editToolbar = CaptureToolbar(actions: .init(
            selectTool: { [weak self] in self?.document.editor.toggleTool($0) },
            undo: { [weak self] in self?.document.editor.undo() },
            watermark: { [weak self] in self?.document.editor.toggleWatermarkPanel() },
            pin: {}, recognizeText: {}, scrollCapture: {},
            cancel: { [weak self] in self?.cancel() },
            save: { [weak self] in self?.save() },
            copy: { [weak self] in self?.copyToPasteboard() }), captureActions: false)
        editToolbar.isHidden = true
        footer.addSubview(editToolbar)
        document.editor.onChange = { [weak self] in self?.layoutFooter() }
        layoutFooter()
    }

    func windowDidResize(_ notification: Notification) { layoutFooter() }

    /// Toolbar centered at the bottom; the sub toolbar or watermark panel above it.
    private func layoutFooter() {
        let bar: NSView = editToolbar.isHidden ? resultBar : editToolbar
        let size = bar.fittingSize
        bar.frame = CGRect(x: (footer.bounds.width - size.width) / 2, y: 8, width: size.width, height: size.height)
        guard !editToolbar.isHidden else { return }
        let editor: AnnotationEditor = document.editor
        editToolbar.update(tool: editor.tool, canUndo: editor.canUndo, watermarkActive: editor.watermarkActive)
        if let panel = editor.secondaryPanel(in: footer) {
            let ps = panel.fittingSize
            panel.frame = CGRect(x: max((footer.bounds.width - ps.width) / 2, 0), y: bar.frame.maxY + 6, width: ps.width, height: ps.height)
        }
    }

    @objc private func startEditing() {
        resultBar.isHidden = true
        editToolbar.isHidden = false
        layoutFooter()
    }

    private func export() -> CGImage? {
        document.editor.render(crop: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }

    @objc private func copyToPasteboard() {
        guard let out = export() else { return }
        if OutputService.copyToPasteboard(out) { ScreenshotHistory.shared.record(out) }
        close()
    }

    @objc private func save() {
        guard let out = export() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.directoryURL = Preferences.saveDirectory
        panel.nameFieldStringValue = FileNaming.screenshotName(for: Date())
        panel.beginSheetModal(for: self) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try OutputService.write(out, to: url)
                Preferences.saveDirectory = url.deletingLastPathComponent()
                ScreenshotHistory.shared.record(out)
                self?.close()
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    @objc private func cancel() { close() }

    func windowWillClose(_ notification: Notification) {
        Self.open.removeAll { $0 === self }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { close() } else { super.keyDown(with: event) }
    }

    #if DEBUG
    /// Test hook: enter editing, add sample marks, render the window content to a PNG.
    static func debugRender(image: CGImage, scale: CGFloat, to url: URL, completion: @escaping () -> Void) {
        show(image: image, scale: scale)
        guard let w = open.last, let content = w.contentView else { return }
        content.wantsLayer = true
        w.startEditing()
        w.document.editor.debugPopulate(in: CGRect(x: 0, y: 0, width: w.document.bounds.width, height: 400))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            content.layoutSubtreeIfNeeded()
            content.displayIfNeeded()
            let size = content.bounds.size
            if let layer = content.layer,
               let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                                   space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                layer.render(in: ctx)
                if let img = ctx.makeImage(), let data = ImageEncoder.png(img) { try? data.write(to: url) }
            }
            if let out = w.export(), let data = ImageEncoder.png(out) {
                try? data.write(to: url.deletingPathExtension().appendingPathExtension("export.png"))
            }
            completion()
        }
    }
    #endif
}

/// The long image at 1 point = `scale` pixels, with the annotation editor on top.
final class LongImageDocumentView: NSView {
    private(set) var editor: AnnotationEditor!
    private var dragging = false

    init(image: CGImage, scale: CGFloat) {
        super.init(frame: CGRect(x: 0, y: 0, width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale))
        wantsLayer = true
        let backdrop = BackdropView(image: image)
        backdrop.frame = bounds
        backdrop.autoresizingMask = [.width, .height]
        addSubview(backdrop)
        editor = AnnotationEditor(host: self, baseImage: image, scale: scale)
        editor.canvas.frame = bounds
        addSubview(editor.canvas)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        editor.commitTextInput()
        editor.closeWatermarkPanel()
        dragging = editor.pointerDown(at: p, clickCount: event.clickCount) == .dragging
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragging else { return }
        editor.pointerDragged(to: convert(event.locationInWindow, from: nil), constrain: event.modifierFlags.contains(.shift))
        autoscroll(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        guard dragging else { return }
        dragging = false
        editor.pointerUp()
    }

    override func keyDown(with event: NSEvent) {
        if !editor.handleKey(event) { super.keyDown(with: event) }
    }

    override func resetCursorRects() {
        addCursorRect(visibleRect, cursor: editor.tool == nil ? .arrow : .crosshair)
    }
}
