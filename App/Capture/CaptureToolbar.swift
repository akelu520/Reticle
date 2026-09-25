import AppKit
import ReticleCore

/// Main toolbar under the selection, in the order of the design spec:
/// 矩形 椭圆 箭头 画笔 高亮 马赛克 文本 标签 ｜ 撤销 ｜ 水印 固定到屏幕 提取文字 滚动截图 ｜ 取消 下载 保存到剪切板
/// The long-screenshot editor uses a reduced set (`captureActions: false`).
final class CaptureToolbar: FloatingPanelView {
    struct Actions {
        var selectTool: (Tool) -> Void
        var undo: () -> Void
        var watermark: () -> Void
        var pin: () -> Void
        var recognizeText: () -> Void
        var scrollCapture: () -> Void
        var cancel: () -> Void
        var save: () -> Void
        var copy: () -> Void
    }

    static let tools: [(Tool, String, String)] = [
        (.rect, "square", "矩形"),
        (.ellipse, "circle", "椭圆"),
        (.arrow, "arrow.up.right", "箭头"),
        (.pen, "scribble.variable", "画笔"),
        (.highlight, "highlighter", "高亮"),
        (.mosaic, "checkerboard.rectangle", "马赛克"),
        (.text, "textformat", "文本"),
        (.label, "mappin.and.ellipse", "标签"),
    ]

    private var toolButtons: [Tool: IconButton] = [:]
    private var undoButton: IconButton!
    private var watermarkButton: IconButton!

    init(actions: Actions, captureActions: Bool = true) {
        super.init()
        for (tool, symbol, tip) in Self.tools {
            let b = IconButton(symbol: symbol, tip: tip) { actions.selectTool(tool) }
            toolButtons[tool] = b
            stack.addArrangedSubview(b)
        }
        addSeparator()
        undoButton = IconButton(symbol: "arrow.uturn.backward", tip: "撤销", handler: actions.undo)
        stack.addArrangedSubview(undoButton)
        addSeparator()
        watermarkButton = IconButton(symbol: "drop", tip: "水印", handler: actions.watermark)
        stack.addArrangedSubview(watermarkButton)
        if captureActions {
            stack.addArrangedSubview(IconButton(symbol: "pin", tip: "固定到屏幕", handler: actions.pin))
            stack.addArrangedSubview(IconButton(symbol: "text.viewfinder", tip: "提取文字", handler: actions.recognizeText))
            stack.addArrangedSubview(IconButton(symbol: "arrow.up.and.down.text.horizontal", tip: "滚动截图", handler: actions.scrollCapture))
        }
        addSeparator()
        stack.addArrangedSubview(IconButton(symbol: "xmark", tip: "取消", handler: actions.cancel))
        stack.addArrangedSubview(IconButton(symbol: "arrow.down.to.line", tip: "下载", handler: actions.save))
        let copy = IconButton(symbol: "checkmark", tip: "保存到剪切板", handler: actions.copy)
        copy.baseTint = Palette.accent
        stack.addArrangedSubview(copy)
    }

    func update(tool: Tool?, canUndo: Bool, watermarkActive: Bool) {
        for (t, b) in toolButtons { b.isSelectedTool = t == tool }
        undoButton.isEnabled = canUndo
        watermarkButton.isSelectedTool = watermarkActive
    }
}
