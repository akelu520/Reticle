import AppKit
import ReticleCore

/// Options for the active tool or the selected annotation: line width (or font
/// size / mosaic mode) on the left, colors on the right.
final class SubToolbar: FloatingPanelView {
    struct Actions {
        var setSize: (SizeLevel) -> Void
        var setColor: (RGBA) -> Void
        var setMosaicMode: (MosaicMode) -> Void
    }

    private let actions: Actions

    init(actions: Actions) {
        self.actions = actions
        super.init(spacing: 4)
    }

    private struct Config: Equatable {
        var tool: Tool
        var preset: ToolPreset
        var mosaicMode: MosaicMode
    }

    private var config: Config?

    /// Rebuilds the controls only when something changed.
    func configure(tool: Tool, preset: ToolPreset, mosaicMode: MosaicMode) {
        let next = Config(tool: tool, preset: preset, mosaicMode: mosaicMode)
        guard next != config else { return }
        config = next
        for v in stack.arrangedSubviews { v.removeFromSuperview() }

        if tool == .mosaic {
            let brush = IconButton(symbol: "paintbrush.pointed", tip: "画笔马赛克", size: 28) { [actions] in actions.setMosaicMode(.brush) }
            let box = IconButton(symbol: "rectangle.dashed", tip: "框选马赛克", size: 28) { [actions] in actions.setMosaicMode(.box) }
            brush.isSelectedTool = mosaicMode == .brush
            box.isSelectedTool = mosaicMode == .box
            stack.addArrangedSubview(brush)
            stack.addArrangedSubview(box)
            if mosaicMode == .brush {
                addSeparator()
                addSizeDots(selected: preset.size)
            }
            return
        }

        if tool.usesFontSize {
            for (level, name, font) in [(SizeLevel.small, "小", 11.0), (.medium, "中", 13.0), (.large, "大", 15.0)] {
                let b = IconButton(title: name, fontSize: font, tip: "文字大小：\(name)") { [actions] in actions.setSize(level) }
                b.isSelectedTool = preset.size == level
                stack.addArrangedSubview(b)
            }
        } else {
            addSizeDots(selected: preset.size)
        }
        addSeparator()
        for color in RGBA.palette {
            let swatch = ColorSwatch(color: color) { [actions] in actions.setColor(color) }
            swatch.isSelected = color == preset.color
            stack.addArrangedSubview(swatch)
        }
    }

    private func addSizeDots(selected: SizeLevel) {
        for (level, d) in [(SizeLevel.small, 4.0), (.medium, 7.0), (.large, 11.0)] {
            let dot = SizeDot(diameter: d) { [actions] in actions.setSize(level) }
            dot.isSelected = level == selected
            dot.toolTip = ["细", "中", "粗"][level.rawValue]
            stack.addArrangedSubview(dot)
        }
    }
}
