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
        /// Selecting recognized text from caret `anchor`.
        case selectText(anchor: Int)
    }

    let snapshot: ScreenSnapshot
    private unowned let session: CaptureSession
    private var scale: CGFloat { snapshot.scale }

    private let backdrop: BackdropView
    private let dimLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()
    private let handlesLayer = CAShapeLayer()
    /// Blue tint over the window under the cursor before a selection exists.
    private let hoverFillLayer = CAShapeLayer()
    private let chrome = LayerHostView()
    private let caret = CaretView()
    /// User drags of the ⠿ handles, kept for the session.
    private var toolbarOffset = CGVector.zero
    private static var modeBarOffset = CGVector.zero
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
        translate: { [weak self] in self?.startRecognition(translate: true) },
        chooseTranslateLanguage: { [weak self] in self?.showTranslateLanguages(from: $0) },
        recognizeText: { [weak self] in self?.startRecognition() },
        recognizeQRCode: { [weak self] in self?.showQRCodes() },
        scrollCapture: { [weak self] in self.map { $0.session.startScrollCapture(from: $0) } },
        cancel: { [weak self] in self?.session.cancel() },
        save: { [weak self] in self.map { $0.session.save(from: $0) } },
        copy: { [weak self] in self.map { $0.session.copy(from: $0) } }))
    private func toolbarDragged(_ d: CGVector) {
        toolbarOffset.dx += d.dx
        toolbarOffset.dy += d.dy
        layoutPanels()
    }

    private lazy var modeBar: ModeBar = {
        let bar = ModeBar { [weak self] in self?.session.setMode($0) }
        bar.onDrag = { [weak self] d in
            Self.modeBarOffset.dx += d.dx
            Self.modeBarOffset.dy += d.dy
            self?.layoutModeBar()
        }
        return bar
    }()
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
    /// Recognized text in the selection, selectable in place.
    private var liveText: LiveTextOverlay!
    /// What the selection contains, for enabling 提取文字 / 识别二维码; nil until scanned.
    private var scanResult: ScanResult?
    private var scannedSelection: CGRect?
    private var pendingScan: DispatchWorkItem?

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
        // Handles: accent dots with a white ring.
        handlesLayer.fillColor = Palette.accent.cgColor
        handlesLayer.strokeColor = NSColor.white.cgColor
        handlesLayer.lineWidth = 1
        hoverFillLayer.fillColor = Palette.accent.withAlphaComponent(0.22).cgColor
        chrome.frame = bounds
        chrome.autoresizingMask = [.width, .height]
        for l in [dimLayer, hoverFillLayer, borderLayer, handlesLayer] {
            l.actions = ["path": NSNull(), "hidden": NSNull(), "lineWidth": NSNull()]
            chrome.hostedLayer.addSublayer(l)
        }
        addSubview(chrome)

        editor.canvas.isHidden = true
        addSubview(editor.canvas)
        liveText = LiveTextOverlay(in: self)
        sizeLabel.isHidden = true
        addSubview(sizeLabel)
        magnifier.isHidden = true
        addSubview(magnifier)

        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect, .cursorUpdate],
                                       owner: self, userInfo: nil))
        toolbar.onDrag = { [weak self] in self?.toolbarDragged($0) }
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
                if editor.tool == nil, session.mode == .screenshot, let caret = liveText.caret(onTextAt: p) {
                    // Over recognized text: select it (double-click a word, triple-click a line).
                    switch event.clickCount {
                    case 2: liveText.select(liveText.word(at: caret))
                    case 3...: liveText.select(liveText.line(at: caret))
                    default:
                        liveText.select(caret..<caret)
                        drag = .selectText(anchor: caret)
                    }
                    return
                }
                liveText.select(0..<0)
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
        case let .selectText(anchor):
            liveText.select(liveText.range(from: anchor, to: liveText.caret(nearest: p)), showsButton: false)
            return
        case nil:
            return
        }
        // The selection changes: recognized text no longer matches it.
        liveText.clear()
        hidePanels()
        updateChrome()
    }

    override func mouseUp(with event: NSEvent) {
        if case .selectText = drag {
            drag = nil
            liveText.select(liveText.selected)
            return
        }
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
        #if DEBUG
        DispatchQueue.main.async { [weak self] in self?.debugDumpLayout() }
        #endif
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
        // ⌘C with text selected in the image copies the text.
        if event.keyCode == 8, event.modifierFlags.contains(.command), liveText.copySelection() { return }
        if editor.handleKey(event) { return }
        // ⌘C while the loupe shows: copy the color under the cursor, then leave.
        if event.keyCode == 8, event.modifierFlags.contains(.command), !magnifier.isHidden, selection == nil || drag != nil {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(magnifier.colorString, forType: .string)
            session.cancel()
            return
        }
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

    /// Shift toggles the loupe between RGB and HEX.
    override func flagsChanged(with event: NSEvent) {
        let shift = event.modifierFlags.contains(.shift)
        if shift, !shiftDown { magnifier.showsHex.toggle() }
        shiftDown = shift
    }

    private var shiftDown = false

    private func nudge(dx: CGFloat, dy: CGFloat) {
        guard let sel = selection else { return }
        selection = SelectionGeometry.move(sel, by: CGVector(dx: dx, dy: dy), within: bounds)
        updateChrome()
    }

    private func editorChanged() {
        if editor.tool != nil { liveText.select(0..<0) }
        // With a drawing tool active the selection shows only its outline, no handles.
        handlesLayer.isHidden = selection == nil || editor.tool != nil
        #if DEBUG
        defer { DispatchQueue.main.async { [weak self] in self?.debugDumpLayout() } }
        #endif
        toolbar.update(.init(tool: editor.tool, canUndo: editor.canUndo, watermarkActive: editor.watermarkActive,
                             hasText: scanResult?.hasText ?? true, hasQRCode: !(scanResult?.codes.isEmpty ?? true), canScrollCapture: editor.model.document.annotations.isEmpty))
        if drag == nil { layoutPanels() }
    }

    /// 翻译 ▾: pick the target language.
    private func showTranslateLanguages(from button: NSView) {
        let menu = NSMenu()
        for (code, name) in TranslationLanguages.all {
            let item = NSMenuItem(title: name, action: #selector(pickTranslateLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = code
            item.state = code == Preferences.translationTarget ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: CGPoint(x: 0, y: button.bounds.maxY + 4), in: button)
    }

    @objc private func pickTranslateLanguage(_ item: NSMenuItem) {
        Preferences.translationTarget = item.representedObject as? String
    }

    // MARK: - Text recognition

    private func selectionImage() -> CGImage? {
        selection.flatMap { Compositor.crop(snapshot.image, to: CoordinateSpace.pixelRect(fromPoints: $0, scale: scale)) }
    }

    private func openTextPanel(title: String) -> TextRecognitionPanel {
        editor.commitTextInput()
        editor.closeWatermarkPanel()
        let panel = textPanel ?? TextRecognitionPanel(actions: .init(
            close: { [weak self] in self?.resetSelection() },
            openLink: { [weak self] in self?.session.open($0) },
            escape: { [weak self] in self?.session.cancel() }))
        if panel.superview == nil { addSubview(panel) }
        textPanel = panel
        panel.title = title
        recognitionToken += 1
        return panel
    }

    /// 识别二维码: the payloads found by the last scan, one per line.
    private func showQRCodes() {
        guard let codes = scanResult?.codes, !codes.isEmpty else { return }
        openTextPanel(title: "识别二维码").show(text: codes.joined(separator: "\n"))
        layoutPanels()
    }

    /// Scans the selection once it settles, to enable 提取文字 / 识别二维码.
    private func scheduleScan() {
        guard let sel = selection else {
            scannedSelection = nil
            scanResult = nil
            return
        }
        guard drag == nil, sel != scannedSelection, session.mode == .screenshot else { return }
        scannedSelection = sel
        scanResult = nil
        liveText.clear()
        // Until the scan answers, 识别二维码 is unavailable.
        editorChanged()
        pendingScan?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.window != nil, let image = self.selectionImage() else { return }
            Task { @MainActor [weak self] in
                // Unknown stays optimistic for text, so a worker failure never hides 提取文字.
                let result = (try? await WorkerClient.scan(image)) ?? ScanResult(hasText: true, codes: [])
                // The session may have ended meanwhile; it detaches the view from its window.
                guard let self, self.window != nil, self.scannedSelection == sel else { return }
                self.scanResult = result
                self.editorChanged()
                if result.hasText { self.recognizeLiveText(in: image, for: sel) }
            }
        }
        pendingScan = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    /// Recognizes the selection's text in the background so it can be selected in place.
    private func recognizeLiveText(in image: CGImage, for sel: CGRect) {
        Task { @MainActor [weak self] in
            let lines = (try? await WorkerClient.recognizeLines(in: image)) ?? []
            guard let self, self.window != nil, self.scannedSelection == sel, self.selection == sel else { return }
            self.liveText.set(LiveTextLayout(lines: lines), frame: sel)
        }
    }

    private func startRecognition(translate: Bool = false) {
        guard let image = selectionImage() else { return }
        let panel = openTextPanel(title: "提取文字")
        panel.showLoading()
        layoutPanels()
        let token = recognitionToken
        Task { @MainActor [weak self] in
            do {
                // Vision runs in ReticleWorker so its models do not stay resident here.
                let text = try await WorkerClient.recognizeText(in: image)
                guard let self, self.window != nil, self.recognitionToken == token else { return }
                panel.show(text: text)
                if translate { panel.translateNow(to: Preferences.translationTarget) }
            } catch {
                guard let self, self.window != nil, self.recognitionToken == token else { return }
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
        liveText.clear()
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
        scheduleScan()

        let highlight = selection ?? hoverRect
        let dim = CGMutablePath()
        dim.addRect(bounds)
        if let r = highlight, isActive { dim.addRect(r) }
        dimLayer.path = dim

        // Before selecting: the window under the cursor is tinted blue with a bold edge.
        // Over the bare desktop (the whole screen) there is nothing to tint.
        if selection == nil, let r = hoverRect, isActive, r != bounds {
            hoverFillLayer.path = CGPath(rect: r, transform: nil)
            hoverFillLayer.isHidden = false
        } else {
            hoverFillLayer.isHidden = true
        }

        if let r = highlight, isActive, selection != nil || r != bounds {
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
                handles.addEllipse(in: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6))
            }
            handlesLayer.path = handles
            handlesLayer.isHidden = editor.tool != nil
            canvas.frame = sel
            canvas.isHidden = false
        } else {
            handlesLayer.isHidden = true
            canvas.isHidden = true
        }

        if let sel = selection {
            // Size in points, "500 x 380", above the selection's top-left corner.
            sizeLabel.text = "\(Int(sel.width.rounded())) x \(Int(sel.height.rounded()))"
            let size = sizeLabel.fittingSize
            let y = sel.minY - size.height - 14 >= 0 ? sel.minY - size.height - 14 : sel.minY + 6
            sizeLabel.frame = CGRect(x: min(max(sel.minX, 0), bounds.maxX - size.width), y: y, width: size.width, height: size.height)
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
            // On whole pixels: a fractional origin makes the scrolling text inside shimmer.
            panel.frame = backingAlignedRect(CGRect(origin: CGPoint(x: x, y: y), size: size), options: .alignAllEdgesNearest)
            panel.isHidden = false
        }

        switch session.mode {
        case .recognizeText:
            // The text panel replaces the toolbars.
            liveText.clear()
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
            let origin = place(toolbar, near: sel, offset: toolbarOffset)
            guard let panel = editor.secondaryPanel(in: self) else {
                caret.isHidden = true
                return
            }
            let ps = panel.fittingSize
            // Below the toolbar when the toolbar sits below the selection, otherwise above it.
            let below = origin.y >= sel.maxY
            let gap = Self.panelGap + SubToolbar.caretHeight
            var y = below ? toolbar.frame.maxY + gap : toolbar.frame.minY - gap - ps.height
            if y + ps.height > bounds.maxY { y = toolbar.frame.minY - gap - ps.height }
            if y < bounds.minY { y = toolbar.frame.maxY + gap }
            // Start the panel near the tool it belongs to, with a caret pointing at the tool.
            let anchor = editor.watermarkPanelOpen ? toolbar.watermarkAnchor(in: self)
                : editor.tool.flatMap { toolbar.anchor(of: $0, in: self) } ?? CGPoint(x: toolbar.frame.minX + 40, y: toolbar.frame.midY)
            let x = min(max(anchor.x - 36, toolbar.frame.minX, bounds.minX), bounds.maxX - ps.width)
            panel.frame = CGRect(x: x, y: y, width: ps.width, height: ps.height)
            let caretBelowToolbar = y > toolbar.frame.midY
            if caret.superview == nil { addSubview(caret) }
            caret.frame = CGRect(x: anchor.x - 7, y: caretBelowToolbar ? y - SubToolbar.caretHeight : y + ps.height,
                                 width: 14, height: SubToolbar.caretHeight)
            caret.pointsUp = caretBelowToolbar
            caret.isHidden = false
            addSubview(caret, positioned: .above, relativeTo: panel)
        }
    }

    @discardableResult
    private func place(_ bar: NSView, near sel: CGRect, offset: CGVector = .zero) -> CGPoint {
        if bar.superview == nil { addSubview(bar) }
        let size = bar.fittingSize
        var origin = SelectionGeometry.toolbarOrigin(for: sel, toolbar: size, within: bounds)
        origin.x = min(max(origin.x + offset.dx, bounds.minX), bounds.maxX - size.width)
        origin.y = min(max(origin.y + offset.dy, bounds.minY), bounds.maxY - size.height)
        bar.frame = CGRect(origin: origin, size: size)
        bar.isHidden = false
        return origin
    }

    /// Mode switcher at the top (draggable), only before a selection exists.
    private func layoutModeBar() {
        let visible = selection == nil && isActive && drag == nil
        if visible, modeBar.superview == nil {
            addSubview(modeBar)
            modeBar.update(mode: session.mode)
        }
        guard modeBar.superview != nil else { return }
        modeBar.isHidden = !visible
        let size = modeBar.fittingSize
        let x = min(max((bounds.width - size.width) / 2 + Self.modeBarOffset.dx, 0), bounds.width - size.width)
        let y = min(max(4 + Self.modeBarOffset.dy, 0), bounds.height - size.height)
        modeBar.frame = CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func hideSelectionPanels() {
        caret.isHidden = true
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

    /// The loupe sits to the lower left of the cursor, flipping when it would leave the screen.
    private func showMagnifier(at p: CGPoint) {
        magnifier.isHidden = false
        magnifier.update(cursor: p)
        let size = magnifier.frame.size
        var origin = CGPoint(x: p.x - 10 - size.width, y: p.y + 10)
        if origin.x < bounds.minX { origin.x = p.x + 10 }
        if origin.y + size.height > bounds.maxY { origin.y = p.y - 10 - size.height }
        magnifier.setFrameOrigin(origin)
    }

    private func updateCursor(at p: CGPoint) {
        guard let sel = selection else {
            CaptureCursor.reticle.set()
            return
        }
        if let h = SelectionGeometry.handle(at: p, in: sel) {
            cursor(for: h).set()
        } else if sel.contains(p) {
            let c = session.mode == .screenshot ? editor.cursor(at: p) : .openHand
            // Over recognized text (and no annotation): the text can be selected.
            (c == .openHand && session.mode == .screenshot && liveText.contains(p) ? .iBeam : c).set()
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

    /// `RETICLE_LAYOUT_OUT=file`: writes each visible toolbar control's center (CG global points) as "name x y" lines.
    func debugDumpLayout() {
        guard let out = ProcessInfo.processInfo.environment["RETICLE_LAYOUT_OUT"], let window else { return }
        var lines: [String] = []
        func visit(_ v: NSView) {
            if !v.isHiddenOrHasHiddenAncestor, let name = (v as? IconButton)?.tip ?? (v as? ModeButton)?.title ?? (v is ColorSwatch || v is SizeDot ? v.accessibilityLabel() ?? "swatch" : nil) {
                let r = window.convertToScreen(v.convert(v.bounds, to: nil))
                let primary = NSScreen.screens.first?.frame.height ?? 0
                lines.append("\(name) \(r.midX) \(primary - r.midY)")
            }
            v.subviews.forEach(visit)
        }
        visit(self)
        try? lines.joined(separator: "\n").write(toFile: out, atomically: true, encoding: .utf8)
    }
    var debugHoverRect: CGRect? { hoverRect }
    var debugEditor: AnnotationEditor { editor }
    var debugLiveText: LiveTextOverlay { liveText }

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
        // White badge, dark text: "500 x 380".
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.cgColor
        layer?.cornerRadius = 4
        field.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        field.textColor = Palette.icon
        field.translatesAutoresizingMaskIntoConstraints = false
        addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            field.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            field.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            field.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}

/// Capture cursor: a crosshair through a small circle, outlined so it reads on any background.
enum CaptureCursor {
    static let reticle: NSCursor = {
        let size = CGSize(width: 24, height: 24)
        let image = NSImage(size: size, flipped: false) { r in
            let c = CGPoint(x: r.midX, y: r.midY)
            func strokes(_ path: NSBezierPath) {
                path.lineWidth = 3
                NSColor.black.withAlphaComponent(0.55).setStroke()
                path.stroke()
                path.lineWidth = 1.2
                NSColor.white.setStroke()
                path.stroke()
            }
            let cross = NSBezierPath()
            cross.move(to: CGPoint(x: c.x, y: r.minY + 1)); cross.line(to: CGPoint(x: c.x, y: r.maxY - 1))
            cross.move(to: CGPoint(x: r.minX + 1, y: c.y)); cross.line(to: CGPoint(x: r.maxX - 1, y: c.y))
            strokes(cross)
            strokes(NSBezierPath(ovalIn: CGRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10)))
            return true
        }
        return NSCursor(image: image, hotSpot: CGPoint(x: 12, y: 12))
    }()
}
