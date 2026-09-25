import AppKit
import ReticleCore

/// 提取文字面板：editable recognized text with clickable links, 复制 (full text),
/// 关闭 (re-select), and 翻译 on macOS 15+.
final class TextRecognitionPanel: NSView, NSTextViewDelegate {
    struct Actions {
        var close: () -> Void
        var openLink: (URL) -> Void
        var escape: () -> Void
    }

    static let size = CGSize(width: 340, height: 280)

    private let actions: Actions
    private let textView = PanelTextView()
    private let status = NSTextField(labelWithString: "")
    private let copyButton = NSButton(title: "复制", target: nil, action: nil)
    private let translateButton = NSButton(title: "翻译", target: nil, action: nil)
    private let targetPopup = NSPopUpButton()
    private let downloadButton = NSButton(title: "去下载", target: nil, action: nil)
    private var original = ""
    private var translated: String?
    private var showingTranslation = false
    private var translatorBox: AnyObject?

    init(actions: Actions) {
        self.actions = actions
        super.init(frame: CGRect(origin: .zero, size: Self.size))
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.cgColor
        layer?.cornerRadius = 8
        shadow = {
            let s = NSShadow()
            s.shadowBlurRadius = 10
            s.shadowOffset = CGSize(width: 0, height: -2)
            s.shadowColor = NSColor.black.withAlphaComponent(0.3)
            return s
        }()
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func viewDidMoveToWindow() { appearance = NSAppearance(named: .aqua) }
    override func mouseDown(with event: NSEvent) {}

    private func build() {
        let title = NSTextField(labelWithString: "提取文字")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.frame = CGRect(x: 14, y: 10, width: 200, height: 18)
        addSubview(title)

        let close = IconButton(symbol: "xmark", tip: "关闭", size: 24) { [actions] in actions.close() }
        close.translatesAutoresizingMaskIntoConstraints = true
        close.frame = CGRect(x: Self.size.width - 34, y: 7, width: 24, height: 24)
        addSubview(close)

        let scroll = NSScrollView(frame: CGRect(x: 10, y: 36, width: Self.size.width - 20, height: Self.size.height - 36 - 46))
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        textView.frame = CGRect(origin: .zero, size: scroll.contentSize)
        textView.autoresizingMask = [.width]
        textView.isRichText = false
        textView.font = .systemFont(ofSize: 13)
        textView.textColor = .black
        textView.drawsBackground = false
        textView.textContainerInset = CGSize(width: 2, height: 4)
        textView.isAutomaticLinkDetectionEnabled = false
        textView.delegate = self
        textView.onEscape = { [actions] in actions.escape() }
        scroll.documentView = textView
        addSubview(scroll)

        status.textColor = .secondaryLabelColor
        status.alignment = .center
        status.frame = CGRect(x: 10, y: 120, width: Self.size.width - 20, height: 20)
        addSubview(status)

        let footerY = Self.size.height - 38
        copyButton.bezelStyle = .rounded
        copyButton.target = self
        copyButton.action = #selector(copyAll)
        copyButton.frame = CGRect(x: Self.size.width - 84, y: footerY, width: 74, height: 28)
        addSubview(copyButton)

        if #available(macOS 15, *) {
            for (code, name) in TranslationLanguages.all {
                targetPopup.addItem(withTitle: name)
                targetPopup.lastItem?.representedObject = code
            }
            targetPopup.frame = CGRect(x: 10, y: footerY + 2, width: 110, height: 24)
            targetPopup.controlSize = .small
            targetPopup.target = self
            targetPopup.action = #selector(targetChanged)
            addSubview(targetPopup)
            translateButton.bezelStyle = .rounded
            translateButton.target = self
            translateButton.action = #selector(toggleTranslation)
            translateButton.frame = CGRect(x: 124, y: footerY, width: 74, height: 28)
            addSubview(translateButton)
            let translator = Translator()
            translatorBox = translator
            addSubview(translator.hostView)
            downloadButton.bezelStyle = .rounded
            downloadButton.target = self
            downloadButton.action = #selector(openLanguageSettings)
            downloadButton.frame = CGRect(x: Self.size.width - 84 - 80, y: footerY, width: 76, height: 28)
            downloadButton.isHidden = true
            addSubview(downloadButton)
        }
        showLoading()
    }

    func showLoading() {
        setText("")
        status.stringValue = "识别中…"
        setControlsEnabled(false)
    }

    func show(text: String) {
        original = text
        translated = nil
        showingTranslation = false
        translateButton.title = "翻译"
        if text.isEmpty {
            setText("")
            status.stringValue = "未识别到文字"
            setControlsEnabled(false)
            return
        }
        status.stringValue = ""
        setText(text)
        setControlsEnabled(true)
        selectTarget(TranslationLanguages.defaultTarget(for: text))
        window?.makeFirstResponder(textView)
    }

    func show(error: Error) {
        setText("")
        status.stringValue = "识别失败：\(error.localizedDescription)"
        setControlsEnabled(false)
    }

    private func setControlsEnabled(_ on: Bool) {
        copyButton.isEnabled = on
        translateButton.isEnabled = on
        targetPopup.isEnabled = on
    }

    /// Sets the text and turns detected web links into clickable links.
    private func setText(_ text: String) {
        let attributed = NSMutableAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.black,
        ])
        for link in LinkDetector.links(in: text) {
            attributed.addAttribute(.link, value: link.url, range: link.range)
        }
        textView.textStorage?.setAttributedString(attributed)
    }

    private func selectTarget(_ code: String) {
        if let item = targetPopup.itemArray.first(where: { ($0.representedObject as? String) == code }) {
            targetPopup.select(item)
        }
    }

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        if let url = link as? URL { actions.openLink(url) }
        return true
    }

    @objc private func copyAll() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(textView.string, forType: .string)
        copyButton.title = "已复制"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.copyButton.title = "复制" }
    }

    @objc private func targetChanged() {
        translated = nil
        if showingTranslation { runTranslation() }
    }

    @objc private func toggleTranslation() {
        if showingTranslation {
            // Back to the original; keep the user's edits to the translation out of it.
            showingTranslation = false
            translateButton.title = "翻译"
            setText(original)
            return
        }
        original = textView.string
        if let translated {
            showTranslation(translated)
        } else {
            runTranslation()
        }
    }

    private func runTranslation() {
        guard #available(macOS 15, *), let translator = translatorBox as? Translator,
              let target = targetPopup.selectedItem?.representedObject as? String else { return }
        translateButton.isEnabled = false
        downloadButton.isHidden = true
        status.stringValue = "翻译中…"
        let text = original
        Task { @MainActor [weak self] in
            switch await Translator.readiness(source: TranslationLanguages.detectedSource(for: text), target: target) {
            case .ready:
                self?.performTranslation(translator, text: text, target: target)
            case .needsDownload:
                self?.translateButton.isEnabled = true
                self?.status.stringValue = "首次翻译需下载语言包：系统设置 › 通用 › 语言与地区 › 翻译语言"
                self?.downloadButton.isHidden = false
            case .unsupported:
                self?.translateButton.isEnabled = true
                self?.status.stringValue = "暂不支持该语言的翻译"
            }
        }
    }

    @available(macOS 15, *)
    private func performTranslation(_ translator: Translator, text: String, target: String) {
        translator.translate(text, to: target) { [weak self] result in
            guard let self else { return }
            self.translateButton.isEnabled = true
            self.status.stringValue = ""
            switch result {
            case let .success(text):
                self.translated = text
                self.showTranslation(text)
            case let .failure(error):
                self.status.stringValue = "翻译失败：\(error.localizedDescription)"
            }
        }
    }

    @objc private func openLanguageSettings() {
        // Goes through openLink so the capture overlay closes and Settings is visible.
        if let url = URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension") {
            actions.openLink(url)
        }
    }

    private func showTranslation(_ text: String) {
        showingTranslation = true
        translateButton.title = "原文"
        setText(text)
    }
}

private final class PanelTextView: NSTextView {
    var onEscape: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}
