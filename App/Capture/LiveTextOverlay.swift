import AppKit
import ReticleCore

/// Text in the selection that can be selected in place and copied, like Live Text.
///
/// Holds the recognized layout for the current selection rect, draws the highlight and
/// shows a 复制 button next to the selected text. Points are in the overlay's (flipped)
/// coordinates; the layout itself is normalized to the selection.
@MainActor
final class LiveTextOverlay {
    private let host = LayerHostView()
    private let highlight = CAShapeLayer()
    private let copyButton = NSButton(title: "复制", target: nil, action: nil)
    private var layout: LiveTextLayout?
    /// The selection rect the layout was recognized for.
    private var frame: CGRect = .zero
    private(set) var selected: Range<Int> = 0..<0

    init(in parent: NSView) {
        host.frame = parent.bounds
        host.autoresizingMask = [.width, .height]
        highlight.fillColor = Palette.accent.withAlphaComponent(0.3).cgColor
        highlight.actions = ["path": NSNull(), "hidden": NSNull()]
        host.hostedLayer.addSublayer(highlight)
        parent.addSubview(host)

        copyButton.isBordered = false
        copyButton.wantsLayer = true
        copyButton.layer?.backgroundColor = NSColor.white.cgColor
        copyButton.layer?.cornerRadius = 6
        copyButton.shadow = {
            let s = NSShadow()
            s.shadowBlurRadius = 6
            s.shadowOffset = CGSize(width: 0, height: -1)
            s.shadowColor = NSColor.black.withAlphaComponent(0.25)
            return s
        }()
        setButtonTitle("复制")
        copyButton.target = self
        copyButton.action = #selector(copyTapped)
        copyButton.isHidden = true
        parent.addSubview(copyButton)
    }

    var isReady: Bool { layout.map { !$0.isEmpty } ?? false }
    var selectedText: String? {
        guard let layout, !selected.isEmpty else { return nil }
        return layout.text(in: selected)
    }

    /// New recognized text for the selection `frame`, or nil to drop it.
    func set(_ layout: LiveTextLayout?, frame: CGRect) {
        self.layout = layout
        self.frame = frame
        select(0..<0)
    }

    func clear() {
        guard layout != nil || !selected.isEmpty else { return }
        set(nil, frame: .zero)
    }

    // MARK: - Hit testing

    private func normalized(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - frame.minX) / max(frame.width, 1), y: (p.y - frame.minY) / max(frame.height, 1))
    }

    private func view(_ r: CGRect) -> CGRect {
        CGRect(x: frame.minX + r.minX * frame.width, y: frame.minY + r.minY * frame.height,
               width: r.width * frame.width, height: r.height * frame.height)
    }

    func contains(_ p: CGPoint) -> Bool {
        layout?.contains(normalized(p)) ?? false
    }

    /// The caret under `p` when `p` is over text.
    func caret(onTextAt p: CGPoint) -> Int? {
        guard let layout, contains(p) else { return nil }
        return layout.caret(at: normalized(p))
    }

    /// The caret nearest `p`, for extending a drag.
    func caret(nearest p: CGPoint) -> Int {
        layout?.caret(at: normalized(p)) ?? 0
    }

    func range(from a: Int, to b: Int) -> Range<Int> { layout?.range(from: a, to: b) ?? 0..<0 }
    func word(at caret: Int) -> Range<Int> { layout?.word(at: caret) ?? 0..<0 }
    func line(at caret: Int) -> Range<Int> { layout?.line(at: caret) ?? 0..<0 }

    // MARK: - Selection

    /// Highlights `range`; the 复制 button appears once `showsButton` (after the drag ends).
    func select(_ range: Range<Int>, showsButton: Bool = true) {
        selected = range
        let rects = layout.map { l in l.highlightRects(for: range).map(view) } ?? []
        let path = CGMutablePath()
        for r in rects { path.addRoundedRect(in: r.insetBy(dx: -1, dy: -1), cornerWidth: 2, cornerHeight: 2) }
        highlight.path = path
        highlight.isHidden = rects.isEmpty
        placeButton(near: rects, visible: showsButton && !rects.isEmpty)
    }

    /// Above the first selected line, or below the last one when there is no room above.
    private func placeButton(near rects: [CGRect], visible: Bool) {
        setButtonTitle("复制")
        guard visible, let first = rects.first, let last = rects.last, let parent = copyButton.superview else {
            copyButton.isHidden = true
            return
        }
        let size = CGSize(width: copyButton.intrinsicContentSize.width + 20, height: 26)
        var y = first.minY - 6 - size.height
        if y < parent.bounds.minY { y = last.maxY + 6 }
        let x = min(max(first.minX, parent.bounds.minX + 4), parent.bounds.maxX - size.width - 4)
        copyButton.frame = CGRect(origin: CGPoint(x: x, y: y), size: size)
        copyButton.isHidden = false
    }

    private func setButtonTitle(_ title: String) {
        copyButton.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: Palette.accent,
        ])
    }

    /// Copies the selected text; false when nothing is selected.
    @discardableResult
    func copySelection() -> Bool {
        guard let text = selectedText else { return false }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        setButtonTitle("已复制")
        return true
    }

    @objc private func copyTapped() { copySelection() }

    #if DEBUG
    /// Line boxes in overlay points, for tests.
    var debugLineFrames: [CGRect] {
        guard let layout else { return [] }
        return layout.highlightRects(for: 0..<layout.count).map(view)
    }
    #endif
}
