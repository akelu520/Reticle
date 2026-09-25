import AppKit
import ReticleCore

/// Inline text editor for 文本 and 标签. Its font and origin match what
/// ReticleCore renders, so committing does not make the text jump.
final class TextInputView: NSTextView {
    /// Fires when the text changes, so a label bubble can be re-laid out.
    var onTextChange: ((String) -> Void)?
    /// Esc: end editing (commits, like clicking elsewhere).
    var onFinish: (() -> Void)?

    init(fontSize: CGFloat, color: NSColor, bubble: NSColor?) {
        super.init(frame: CGRect(x: 0, y: 0, width: 40, height: fontSize * 1.4))
        font = .systemFont(ofSize: fontSize)
        textColor = color
        insertionPointColor = color
        isRichText = false
        allowsUndo = true
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isContinuousSpellCheckingEnabled = false
        textContainerInset = .zero
        textContainer?.lineFragmentPadding = 0
        textContainer?.widthTracksTextView = false
        textContainer?.containerSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        isHorizontallyResizable = true
        isVerticallyResizable = true
        maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        wantsLayer = true
        if let bubble {
            drawsBackground = true
            backgroundColor = bubble
            layer?.cornerRadius = fontSize * 0.3
        } else {
            drawsBackground = false
            layer?.borderColor = NSColor(white: 1, alpha: 0.8).cgColor
            layer?.borderWidth = 1
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
    }

    override func didChangeText() {
        super.didChangeText()
        onTextChange?(string)
    }

    override func cancelOperation(_ sender: Any?) {
        onFinish?()
    }
}
