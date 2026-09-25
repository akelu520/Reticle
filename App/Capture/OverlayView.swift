import AppKit
import ReticleCore

/// Full-screen interaction surface for one display: frozen backdrop, dim mask,
/// window hover highlight, selection with handles, size label, magnifier,
/// annotation editing and toolbars. Coordinates are flipped (origin top-left)
/// to match ReticleCore geometry; annotation coordinates are image pixels.
@MainActor
final class OverlayView: NSView {
    private enum Drag {
        case create(start: CGPoint, snap: CGRect?)
        case move(start: CGPoint, original: CGRect)
        case resize(SelectionHandle)
        case annotate
    }

    let snapshot: ScreenSnapshot
    private unowned let session: CaptureSession
    private var scale: CGFloat { snapshot.scale }

    private let backdrop: BackdropView
    private let dimLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()
    private let handlesLayer = CAShapeLayer()
    private let chrome = LayerHostView()
    private let sizeLabel = SizeLabel()
    private let magnifier: MagnifierView
    private lazy var editor: AnnotationEditor = {
        let e = AnnotationEditor(host: self, baseImage: snapshot.image, scale: scale)
        e.onChange = { [weak self] in self?.editorChanged() }
        return e
    }()
    private lazy var toolbar = CaptureToolbar(actions: .init(
        selectTool: { [weak self] in self?.editor.toggleTool($0) },
        undo: { [weak self] in self?.editor.undo() },
        watermark: { [weak self] in self?.editor.toggleWatermarkPanel() },
        pin: { [weak self] in self.map { $0.session.pin(from: $0) } },
        recognizeText: { [weak self] in self?.startRecognition() },
        scrollCapture: { [weak self] in self.map { $0.session.startScrollCapture(from: $0) } },
        cancel: { [weak self] in self?.session.cancel() },
        save: { [weak self] in self.map { $0.session.save(from: $0) } },
        copy: { [weak self] in self.map { $0.session.copy(from: $0) } }))
    private lazy var modeBar = ModeBar { [weak self] in self?.session.setMode($0) }
    private lazy var recordStartBar = RecordStartBar(
        onStart: { [weak self] format in
            guard let self else { return }
            self.session.startRecording(from: self, format: format)
        },
        onCancel: { [weak self] in self?.session.cancel() })
    private lazy var scrollStartBar = ScrollStartBar(
        onStart: { [weak self] in self.map { $0.session.startScrollCapture(from: $0) } },
        onCancel: { [weak self] in self?.session.cancel() })
    private var textPanel: TextRecognitionPanel?
    /// Identifies the latest OCR run so a stale result is ignored.
    private var recognitionToken = 0

    private var hoverRect: CGRect?
    private(set) var selection: CGRect?
    private var drag: Drag?
    private var isActive = true

    private static let dragThreshold: CGFloat = 3
    private static let panelGap: CGFloat = 6

    init(snapshot: ScreenSnapshot, session: CaptureSession) {
        self.snapshot = snapshot
        self.session = session
        self.backdrop = BackdropView(image: snapshot.image)
        self.magnifier = MagnifierView(image: snapshot.image, scale: snapshot.scale)
        super.init(frame: CGRect(origin: .zero, size: snapshot.screen.frame.size))
        wantsLayer = true

        backdrop.frame = bounds
        backdrop.autoresizingMask = [.width, .height]
        addSubview(backdrop)

        dimLayer.fillColor = NSColor.black.withAlphaComponent(0.4).cgColor
        dimLayer.fillRule = .evenOdd
        borderLayer.fillColor = nil
        borderLayer.strokeColor = Palette.accent.cgColor
        handlesLayer.fillColor = NSColor.white.cgColor
        handlesLayer.strokeColor = Palette.accent.cgColor
        handlesLayer.lineWidth = 1
        chrome.frame = bounds
        chrome.autoresizingMask = [.width, .height]
        for l in [dimLayer, borderLayer, handlesLayer] {
            l.actions = ["path": NSNull(), "hidden": NSNull(), "lineWidth": NSNull()]
            chrome.hostedLayer.addSublayer(l)
        }
        addSubview(chrome)

        editor.canvas.isHidden = true
        addSubview(editor.canvas)
        sizeLabel.isHidden = true
        addSubview(sizeLabel)
        magnifier.isHidden = true
        addSubview(magnifier)

        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect, .cursorUpdate],
                                       owner: self, userInfo: nil))
        updateChrome()
        #if DEBUG
        Self.debugLive.append(Weak(self))
        #endif
    }

    #if DEBUG
    final class Weak { weak var value: OverlayView?; init(_ v: OverlayView) { value = v } }
    static var debugLive: [Weak] = []
    static var debugLiveCount: Int { debugLive.filter { $0.value != nil }.count }
    #endif

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        window?.makeFirstResponder(self)
    }

    // MARK: - Session coordination

    /// Another display took the selection: drop ours and show a plain dim.
    func deactivate() {
        isActive = false
        hoverRect = nil
        selection = nil
        drag = nil
        editor.reset()
        closeTextPanel()
        magnifier.isHidden = true
        updateChrome()
    }

    func reactivate() {
        isActive = true
        refreshHover()
    }

    func modeChanged() {
        modeBar.update(mode: session.mode)
    }

    func refreshHover() {
        guard isActive, selection == nil, let window else { return }
        let p = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        guard bounds.contains(p) else {
            hoverRect = nil
            magnifier.isHidden = true
            updateChrome()
            return
        }
        hoverRect = WindowPicker.pick(at: p, windows: snapshot.windows, screen: bounds)
        showMagnifier(at: p)
        updateChrome()
    }

    /// The selection in AppKit global coordinates, for placing windows.
    var selectionGlobalFrame: CGRect? {
        selection.map { CoordinateSpace.appKitGlobal(fromLocalFlipped: $0, screenFrame: snapshot.screen.frame) }
    }

    /// The selected region at full pixel resolution, with annotations burned in.
    func exportImage() -> CGImage? {
        guard let selection else { return nil }
        return editor.render(crop: CoordinateSpace.pixelRect(fromPoints: selection, scale: scale))
    }

    // MARK: - Mouse

    override func mouseMoved(with event: NSEvent) {
        let p = point(event)
        if selection == nil {
            guard isActive else { return }
            hoverRect = WindowPicker.pick(at: p, windows: snapshot.windows, screen: bounds)
            showMagnifier(at: p)
            updateChrome()
        }
        updateCursor(at: p)
    }

    override func cursorUpdate(with event: NSEvent) {
        updateCursor(at: point(event))
    }

    override func mouseDown(with event: NSEvent) {
        let p = point(event)
        editor.commitTextInput()
        editor.closeWatermarkPanel()
        if let sel = selection {
            if let h = SelectionGeometry.handle(at: p, in: sel) {
                drag = .resize(h)
                return
            }
            guard sel.contains(p) else { return }
            // Only the plain screenshot mode edits annotations.
            let result = session.mode == .screenshot ? editor.pointerDown(at: p, clickCount: event.clickCount) : .notHandled
            switch result {
            case .dragging:
                drag = .annotate
            case .handled:
                break
            case .notHandled:
                if editor.tool == nil {
                    if event.clickCount == 2, session.mode == .screenshot {
                        session.copy(from: self)
                        return
                    }
                    drag = .move(start: p, original: sel)
                }
            }
            return
        }
        if !isActive {
            session.selectionCleared()
            isActive = true
        }
        session.selectionStarted(in: self)
        // Snap to the window under the press point; the last hover may be stale
        // (e.g. no mouse move since the overlay appeared).
        drag = .create(start: p, snap: WindowPicker.pick(at: p, windows: snapshot.windows, screen: bounds))
    }

    override func mouseDragged(with event: NSEvent) {
        let p = point(event)
        switch drag {
        case let .create(start, _):
            guard hypot(p.x - start.x, p.y - start.y) > Self.dragThreshold || selection != nil else { return }
            selection = SelectionGeometry.rect(from: start, to: p, within: bounds)
            hoverRect = nil
            showMagnifier(at: p)
        case let .move(start, original):
            selection = SelectionGeometry.move(original, by: CGVector(dx: p.x - start.x, dy: p.y - start.y), within: bounds)
        case let .resize(handle):
            guard let sel = selection else { return }
            selection = SelectionGeometry.resize(sel, handle: handle, to: p, within: bounds)
            showMagnifier(at: p)
        case .annotate:
            editor.pointerDragged(to: p, constrain: event.modifierFlags.contains(.shift))
            return
        case nil:
            return
        }
        hidePanels()
        updateChrome()
    }

    override func mouseUp(with event: NSEvent) {
        if case .annotate = drag {
            drag = nil
            editor.pointerUp()
            return
        }
        if case let .create(_, snap) = drag, selection == nil {
            selection = snap ?? bounds
        }
        if let sel = selection, sel.width < 2 || sel.height < 2 {
            drag = nil
            selection = nil
            refreshHover()
            return
        }
        magnifier.isHidden = true
        let created: Bool
        if case .create = drag { created = true } else { created = false }
        drag = nil
        updateChrome()
        updateCursor(at: point(event))
        if created, session.mode == .recognizeText {
            startRecognition()
        }
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        if editor.handleKey(event) { return }
        switch Int(event.keyCode) {
        case 53: // Esc
            session.cancel()
        case 36, 76: // Return, keypad Enter
            if selection != nil, session.mode == .screenshot { session.copy(from: self) }
        case 123: nudge(dx: -1, dy: 0)
        case 124: nudge(dx: 1, dy: 0)
        case 125: nudge(dx: 0, dy: 1)
        case 126: nudge(dx: 0, dy: -1)
        default:
            super.keyDown(with: event)
        }
    }

    private func nudge(dx: CGFloat, dy: CGFloat) {
        guard let sel = selection else { return }
        selection = SelectionGeometry.move(sel, by: CGVector(dx: dx, dy: dy), within: bounds)
        updateChrome()
    }

    private func editorChanged() {
        toolbar.update(tool: editor.tool, canUndo: editor.canUndo, watermarkActive: editor.watermarkActive)
        if drag == nil { layoutPanels() }
    }

    // MARK: - Text recognition

    private func startRecognition() {
        editor.commitTextInput()
        editor.closeWatermarkPanel()
        guard let selection,
              let image = Compositor.crop(snapshot.image, to: CoordinateSpace.pixelRect(fromPoints: selection, scale: scale)) else { return }
        let panel = textPanel ?? TextRecognitionPanel(actions: .init(
            close: { [weak self] in self?.resetSelection() },
            openLink: { [weak self] in self?.session.open($0) },
            escape: { [weak self] in self?.session.cancel() }))
        if panel.superview == nil { addSubview(panel) }
        textPanel = panel
        panel.showLoading()
        layoutPanels()
        recognitionToken += 1
        let token = recognitionToken
        Task { @MainActor [weak self] in
            do {
                // Vision runs in ReticleWorker so its models do not stay resident here.
                let text = try await WorkerClient.recognizeText(in: image)
                guard let self, self.recognitionToken == token else { return }
                panel.show(text: text)
            } catch {
                guard let self, self.recognitionToken == token else { return }
                panel.show(error: error)
            }
        }
    }

    private func closeTextPanel() {
        recognitionToken += 1
        textPanel?.removeFromSuperview()
        textPanel = nil
    }

    /// 关闭 on the text panel: drop the selection so the user can select again.
    private func resetSelection() {
        closeTextPanel()
        editor.reset()
        selection = nil
        drag = nil
        updateChrome()
        session.selectionCleared()
        window?.makeFirstResponder(self)
    }

    // MARK: - Layout

    private func updateChrome() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let highlight = selection ?? hoverRect
        let dim = CGMutablePath()
        dim.addRect(bounds)
        if let r = highlight, isActive { dim.addRect(r) }
        dimLayer.path = dim

        if let r = highlight, isActive {
            borderLayer.isHidden = false
            borderLayer.lineWidth = selection == nil ? 3 : 1
            let inset = borderLayer.lineWidth / 2
            borderLayer.path = CGPath(rect: r.insetBy(dx: -inset, dy: -inset), transform: nil)
        } else {
            borderLayer.isHidden = true
        }

        let canvas = editor.canvas
        if let sel = selection {
            let handles = CGMutablePath()
            for p in SelectionGeometry.handlePoints(for: sel).values {
                handles.addEllipse(in: CGRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7))
            }
            handlesLayer.path = handles
            handlesLayer.isHidden = false
            canvas.frame = sel
            canvas.isHidden = false
        } else {
            handlesLayer.isHidden = true
            canvas.isHidden = true
        }

        if let sel = selection {
            let px = CoordinateSpace.pixelRect(fromPoints: sel, scale: scale)
            sizeLabel.text = "\(Int(px.width)) × \(Int(px.height))"
            let size = sizeLabel.fittingSize
            let y = sel.minY - size.height - 4 >= 0 ? sel.minY - size.height - 4 : sel.minY + 4
            sizeLabel.frame = CGRect(x: min(sel.minX, bounds.maxX - size.width), y: y, width: size.width, height: size.height)
            sizeLabel.isHidden = false
        } else {
            sizeLabel.isHidden = true
        }

        if drag == nil {
            layoutPanels()
        } else {
            hidePanels()
        }
        canvas.needsDisplay = true
    }

    /// Positions the mode bar, the toolbar for the current mode, and the panel next to it.
    private func layoutPanels() {
        layoutModeBar()
        guard let sel = selection else {
            hideSelectionPanels()
            return
        }
        if let panel = textPanel {
            let size = TextRecognitionPanel.size
            var x = sel.maxX + Self.panelGap
            if x + size.width > bounds.maxX { x = sel.minX - Self.panelGap - size.width }
            if x < bounds.minX { x = bounds.maxX - size.width - Self.panelGap }
            let y = min(max(sel.minY, bounds.minY), bounds.maxY - size.height)
            panel.frame = CGRect(origin: CGPoint(x: x, y: y), size: size)
            panel.isHidden = false
        }

        switch session.mode {
        case .recognizeText:
            // The text panel replaces the toolbars.
            toolbar.isHidden = true
            scrollStartBar.isHidden = true
            editor.hideSecondaryPanels()
        case .scrollCapture:
            toolbar.isHidden = true
            editor.hideSecondaryPanels()
            place(scrollStartBar, near: sel)
        case .record:
            toolbar.isHidden = true
            editor.hideSecondaryPanels()
            place(recordStartBar, near: sel)
        case .screenshot:
            scrollStartBar.isHidden = true
            let origin = place(toolbar, near: sel)
            guard let panel = editor.secondaryPanel(in: self) else { return }
            let ps = panel.fittingSize
            // Below the toolbar when the toolbar sits below the selection, otherwise above it.
            let below = origin.y >= sel.maxY
            var y = below ? toolbar.frame.maxY + Self.panelGap : toolbar.frame.minY - Self.panelGap - ps.height
            if y + ps.height > bounds.maxY { y = toolbar.frame.minY - Self.panelGap - ps.height }
            if y < bounds.minY { y = toolbar.frame.maxY + Self.panelGap }
            let x = min(max(toolbar.frame.minX, bounds.minX), bounds.maxX - ps.width)
            panel.frame = CGRect(x: x, y: y, width: ps.width, height: ps.height)
        }
    }

    @discardableResult
    private func place(_ bar: NSView, near sel: CGRect) -> CGPoint {
        if bar.superview == nil { addSubview(bar) }
        let size = bar.fittingSize
        let origin = SelectionGeometry.toolbarOrigin(for: sel, toolbar: size, within: bounds)
        bar.frame = CGRect(origin: origin, size: size)
        bar.isHidden = false
        return origin
    }

    /// Mode switcher at the top center, only before a selection exists.
    private func layoutModeBar() {
        let visible = selection == nil && isActive && drag == nil && session.mode != .record
        if visible, modeBar.superview == nil {
            addSubview(modeBar)
            modeBar.update(mode: session.mode)
        }
        guard modeBar.superview != nil else { return }
        modeBar.isHidden = !visible
        let size = modeBar.fittingSize
        modeBar.frame = CGRect(x: (bounds.width - size.width) / 2, y: 12, width: size.width, height: size.height)
    }

    private func hideSelectionPanels() {
        textPanel?.isHidden = true
        toolbar.isHidden = true
        scrollStartBar.isHidden = true
        recordStartBar.isHidden = true
        editor.hideSecondaryPanels()
    }

    private func hidePanels() {
        layoutModeBar()
        hideSelectionPanels()
    }

    private func showMagnifier(at p: CGPoint) {
        magnifier.isHidden = false
        magnifier.update(cursor: p, selectionSize: selection.map { CoordinateSpace.pixelRect(fromPoints: $0, scale: scale).size })
        let size = magnifier.frame.size
        var origin = CGPoint(x: p.x + 20, y: p.y + 20)
        if origin.x + size.width > bounds.maxX { origin.x = p.x - 20 - size.width }
        if origin.y + size.height > bounds.maxY { origin.y = p.y - 20 - size.height }
        magnifier.setFrameOrigin(origin)
    }

    private func updateCursor(at p: CGPoint) {
        guard let sel = selection else {
            NSCursor.crosshair.set()
            return
        }
        if let h = SelectionGeometry.handle(at: p, in: sel) {
            cursor(for: h).set()
        } else if sel.contains(p) {
            (session.mode == .screenshot ? editor.cursor(at: p) : .openHand).set()
        } else {
            NSCursor.arrow.set()
        }
    }

    private func cursor(for handle: SelectionHandle) -> NSCursor {
        switch handle {
        case .left, .right: return .resizeLeftRight
        case .top, .bottom: return .resizeUpDown
        case .topLeft, .bottomRight:
            if #available(macOS 15, *) { return .frameResize(position: .topLeft, directions: .all) }
            return .crosshair
        case .topRight, .bottomLeft:
            if #available(macOS 15, *) { return .frameResize(position: .topRight, directions: .all) }
            return .crosshair
        }
    }

    private func point(_ event: NSEvent) -> CGPoint {
        convert(event.locationInWindow, from: nil)
    }

    #if DEBUG
    func debugStartRecognition() { startRecognition() }
    var debugHoverRect: CGRect? { hoverRect }
    var debugEditor: AnnotationEditor { editor }

    /// Test hook: set a selection, optionally add sample annotations, and render the layer tree to a PNG.
    func debugRender(selection sel: CGRect?, cursor: CGPoint, annotate: Bool = false, to url: URL) {
        if let sel { selection = sel } else { hoverRect = WindowPicker.pick(at: cursor, windows: snapshot.windows, screen: bounds) }
        drag = nil
        updateChrome()
        if annotate, let sel { editor.debugPopulate(in: sel) }
        showMagnifier(at: cursor)
        magnifier.isHidden = annotate
        updateChrome()
        layoutSubtreeIfNeeded()
        displayIfNeeded()
        guard let layer else { return }
        let w = Int(bounds.width), h = Int(bounds.height)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        // CALayer.render draws in a y-up context; flip so the output matches the screen.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        layer.render(in: ctx)
        if let img = ctx.makeImage(), let data = ImageEncoder.png(img) { try? data.write(to: url) }
    }
    #endif
}

/// Shows the frozen screen image via layer contents (no CPU redraw).
final class BackdropView: NSView {
    private let image: CGImage

    init(image: CGImage) {
        self.image = image
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var wantsUpdateLayer: Bool { true }
    /// Decoration only: clicks go to the view underneath (overlay or long-image document).
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateLayer() {
        layer?.contents = image
        layer?.contentsGravity = .resize
    }
}

/// Layer-hosting view for the dim mask and selection outline. Hosting (rather
/// than adding sublayers to a layer-backed view) keeps AppKit from reordering them.
final class LayerHostView: NSView {
    let hostedLayer = CALayer()

    init() {
        super.init(frame: .zero)
        hostedLayer.isGeometryFlipped = true
        layer = hostedLayer
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Pixel size badge above the selection.
final class SizeLabel: NSView {
    private let field = NSTextField(labelWithString: "")

    var text: String {
        get { field.stringValue }
        set { field.stringValue = newValue }
    }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.75).cgColor
        layer?.cornerRadius = 4
        field.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        field.textColor = .white
        field.translatesAutoresizingMaskIntoConstraints = false
        addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            field.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            field.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            field.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}
