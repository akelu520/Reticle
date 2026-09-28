import AppKit
import ReticleCore

/// Main toolbar under the selection:
/// ⠿ 矩形 椭圆 直线 箭头 画笔 文本 标签 ｜ 马赛克 高亮 水印 固定到屏幕 翻译▾ 提取文字 识别二维码 滚动截图 ｜ 撤销 下载 取消 保存到剪贴板
/// The long-screenshot editor uses a reduced set (`captureActions: false`).
final class CaptureToolbar: FloatingPanelView {
    struct Actions {
        var selectTool: (Tool) -> Void
        var undo: () -> Void
        var watermark: () -> Void
        var pin: () -> Void = {}
        var translate: () -> Void = {}
        var chooseTranslateLanguage: (NSView) -> Void = { _ in }
        var recognizeText: () -> Void = {}
        var recognizeQRCode: () -> Void = {}
        var scrollCapture: () -> Void = {}
        var cancel: () -> Void
        var save: () -> Void
        var copy: () -> Void
    }

    static let drawingTools: [(Tool, String, String)] = [
        (.rect, "square", "矩形"),
        (.ellipse, "circle", "椭圆"),
        (.line, "line.diagonal", "直线"),
        (.arrow, "arrow.up.right", "箭头"),
        (.pen, "pencil.and.scribble", "画笔"),
        (.text, "reticle.text", "文本"),
        (.label, "tag", "标签"),
    ]

    private var toolButtons: [Tool: IconButton] = [:]
    private var undoButton: IconButton!
    private var watermarkButton: IconButton!
    private var ocrButton: IconButton?
    private var qrButton: IconButton?
    private var scrollButton: IconButton?
    private var languageHandler: ((NSView) -> Void)?

    init(actions: Actions, captureActions: Bool = true) {
        super.init(spacing: 8, insets: NSEdgeInsets(top: 4, left: 6, bottom: 4, right: 10))
        addDragHandle()
        for (tool, symbol, tip) in Self.drawingTools {
            add(tool, symbol, tip, actions)
        }
        addSeparator()
        add(.mosaic, "reticle.mosaic", "马赛克", actions)
        add(.highlight, "reticle.highlight", "高亮", actions)
        watermarkButton = IconButton(symbol: "reticle.watermark", tip: "水印", handler: actions.watermark)
        stack.addArrangedSubview(watermarkButton)
        if captureActions {
            stack.addArrangedSubview(IconButton(symbol: "pin", tip: "固定到屏幕", handler: actions.pin))
            let translate = IconButton(symbol: "reticle.translate", tip: "翻译", handler: actions.translate)
            stack.addArrangedSubview(translate)
            languageHandler = actions.chooseTranslateLanguage
            let chevron = IconButton(symbol: "chevron.down", tip: "翻译语言", size: 14, pointSize: 9) {}
            chevron.target = self
            chevron.action = #selector(chooseLanguage(_:))
            stack.addArrangedSubview(chevron)
            stack.setCustomSpacing(0, after: translate)
            let ocr = IconButton(symbol: "text.viewfinder", tip: "提取文字", handler: actions.recognizeText)
            let qr = IconButton(symbol: "qrcode", tip: "识别二维码", handler: actions.recognizeQRCode)
            let scroll = IconButton(symbol: "reticle.scroll", tip: "滚动截图", handler: actions.scrollCapture)
            [ocr, qr, scroll].forEach(stack.addArrangedSubview)
            ocrButton = ocr
            qrButton = qr
            scrollButton = scroll
        }
        addSeparator()
        undoButton = IconButton(symbol: "arrow.uturn.backward", tip: "撤销", handler: actions.undo)
        stack.addArrangedSubview(undoButton)
        stack.addArrangedSubview(IconButton(symbol: "arrow.down.to.line", tip: "下载", handler: actions.save))
        let cancel = IconButton(symbol: "xmark", tip: "取消", handler: actions.cancel)
        cancel.baseTint = Palette.danger
        stack.addArrangedSubview(cancel)
        let copy = IconButton(symbol: "checkmark", tip: "保存到剪贴板", handler: actions.copy)
        copy.baseTint = Palette.success
        stack.addArrangedSubview(copy)
    }

    @objc private func chooseLanguage(_ sender: NSButton) {
        Tooltip.shared.hide()
        languageHandler?(sender)
    }

    private func add(_ tool: Tool, _ symbol: String, _ tip: String, _ actions: Actions) {
        let b = IconButton(symbol: symbol, tip: tip) { actions.selectTool(tool) }
        toolButtons[tool] = b
        stack.addArrangedSubview(b)
    }

    /// Center of a tool's button in `view` coordinates, for pointing the sub toolbar at it.
    func anchor(of tool: Tool, in view: NSView) -> CGPoint? {
        toolButtons[tool].map { view.convert(CGPoint(x: $0.bounds.midX, y: $0.bounds.midY), from: $0) }
    }

    /// Center of the watermark button, which also owns a sub toolbar.
    func watermarkAnchor(in view: NSView) -> CGPoint {
        view.convert(CGPoint(x: watermarkButton.bounds.midX, y: watermarkButton.bounds.midY), from: watermarkButton)
    }

    struct State {
        var tool: Tool?
        var canUndo: Bool
        var watermarkActive: Bool
        /// 提取文字 / 识别二维码 are offered only when the selection contains text / a QR code.
        var hasText = true
        var hasQRCode = false
        /// 滚动截图 is unavailable once the screenshot has been annotated.
        var canScrollCapture = true
    }

    func update(_ s: State) {
        for (t, b) in toolButtons { b.isSelectedTool = t == s.tool }
        undoButton.isEnabled = s.canUndo
        watermarkButton.isSelectedTool = s.watermarkActive
        ocrButton?.isEnabled = s.hasText
        qrButton?.isEnabled = s.hasQRCode
        scrollButton?.isEnabled = s.canScrollCapture
    }

    /// Used by the long-image editor.
    func update(tool: Tool?, canUndo: Bool, watermarkActive: Bool) {
        update(State(tool: tool, canUndo: canUndo, watermarkActive: watermarkActive))
    }
}
