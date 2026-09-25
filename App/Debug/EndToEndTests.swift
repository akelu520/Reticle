#if DEBUG
import AppKit
import AVFoundation
import AVKit
import ReticleCore

/// In-app end-to-end tests (DEBUG only). Drives the real windows with synthetic
/// mouse and keyboard events, using `RETICLE_DEMO_IMAGE` instead of a live
/// screen capture so no permissions are needed. Run with `RETICLE_E2E=1`.
@MainActor
enum EndToEndTests {
    private static var results: [(name: String, ok: Bool, detail: String)] = []
    private static var notes: [String] = []

    static func run() async -> Int {
        let backup = PasteboardBackup()
        let memoryAtStart = footprintMB()
        let sections: [(String, () async -> Void)] = [
            ("截图：遮罩、窗口识别、选区", testSelection),
            ("标注编辑", testAnnotations),
            ("输出：复制 / 下载 / 取消", testOutputs),
            ("固定到屏幕", testPin),
            ("提取文字与翻译", testTextRecognition),
            ("滚动截图", testScrollCapture),
            ("长图编辑窗口", testLongImageWindow),
            ("录屏：框选与预览导出", testRecording),
            ("设置与快捷键", testSettings),
            ("截图历史", testHistory),
            ("真实屏幕：截图 / 滚动截图 / 录屏", testRealScreen),
        ]
        // RETICLE_E2E_ONLY=0,3 runs a subset (for per-feature memory measurements).
        let only = ProcessInfo.processInfo.environment["RETICLE_E2E_ONLY"].map { Set($0.split(separator: ",").compactMap { Int($0) }) }
        for (index, (title, test)) in sections.enumerated() where only?.contains(index) ?? true {
            print("\n== \(title)")
            await test()
            await endSessionIfNeeded()
            try? await Task.sleep(nanoseconds: 300_000_000)
            print("   内存 \(footprintMB()) MB；存活的遮罩视图 \(OverlayView.debugLiveCount)，遮罩窗口 \(NSApp.windows.filter { $0 is OverlayWindow }.count)")
        }
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        let memoryAtEnd = footprintMB()
        malloc_zone_pressure_relief(nil, 0)
        try? await Task.sleep(nanoseconds: 500_000_000)
        let memoryAfterRelief = footprintMB()
        backup.restore()
        let windows = Dictionary(grouping: NSApp.windows, by: { String(describing: Swift.type(of: $0)) }).mapValues(\.count)
        print("仍存在的窗口：\(windows)")
        if let hold = ProcessInfo.processInfo.environment["RETICLE_E2E_HOLD"], let s = Double(hold) {
            print("pid \(getpid())，保持 \(Int(s)) 秒供外部测量")
            fflush(stdout)
            try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000))
        }

        let failed = results.filter { !$0.ok }
        print("\n== 结果：\(results.count - failed.count)/\(results.count) 通过")
        for f in failed { print("✗ \(f.name) — \(f.detail)") }
        print("内存 phys_footprint：开始 \(memoryAtStart) MB，结束 \(memoryAtEnd) MB，归还空闲堆内存后 \(memoryAfterRelief) MB")
        for n in notes { print("注：\(n)") }
        return failed.count
    }

    // MARK: - Sections

    static func testSelection() async {
        guard var v = await startSession(.screenshot) else { return }
        let b = v.bounds
        let win = CGRect(x: b.width * 0.1, y: b.height * 0.1, width: b.width * 0.4, height: b.height * 0.5)

        mouse(v, .mouseMoved, CGPoint(x: win.midX, y: win.midY))
        check("悬停识别窗口", approx(v.debugHoverRect, win), "\(String(describing: v.debugHoverRect))")
        mouse(v, .mouseMoved, CGPoint(x: b.width * 0.8, y: b.height * 0.8))
        check("悬停空白处高亮整屏", v.debugHoverRect == b)
        check("顶部模式栏显示 截图/滚动截图/提取文字",
              ["截图", "滚动截图", "提取文字"].allSatisfy { visibleButton(in: v, title: $0) != nil })

        let other = await startSession(.screenshot) ?? v
        click(other, CGPoint(x: win.midX, y: win.midY)) // no mouse move first: must still snap to the window
        check("单击选中窗口（未先移动鼠标）", approx(other.selection, win), "\(String(describing: other.selection))")
        v = other
        check("出现主工具栏", visibleButton(in: v, tip: "保存到剪切板") != nil)
        check("模式栏在选区后隐藏", visibleButton(in: v, title: "滚动截图") == nil)

        drag(v, from: CGPoint(x: win.maxX, y: win.maxY), to: CGPoint(x: win.maxX + 50, y: win.maxY + 30))
        check("拖动右下角手柄调整大小", approx(v.selection?.size, CGSize(width: win.width + 50, height: win.height + 30)), "\(String(describing: v.selection))")

        let before = v.selection ?? .zero
        drag(v, from: CGPoint(x: before.midX, y: before.midY), to: CGPoint(x: before.midX + 20, y: before.midY + 10))
        check("拖动选区移动", approx(v.selection?.origin, CGPoint(x: before.minX + 20, y: before.minY + 10)), "\(String(describing: v.selection))")

        let moved = v.selection ?? .zero
        key(v, 124)
        key(v, 125)
        check("方向键微调", approx(v.selection?.origin, CGPoint(x: moved.minX + 1, y: moved.minY + 1)), "\(String(describing: v.selection))")

        let dragged = CGRect(x: 200, y: 150, width: 300, height: 200)
        key(v, 53)
        _ = await waitUntil { overlay() == nil }
        guard let v2 = await startSession(.screenshot) else { return }
        drag(v2, from: dragged.origin, to: CGPoint(x: dragged.maxX, y: dragged.maxY))
        check("拖拽框选任意区域", v2.selection == dragged, "\(String(describing: v2.selection))")
        let sizeBadge = descendants(of: v2, SizeLabel.self).first
        let px = CoordinateSpace.pixelRect(fromPoints: dragged, scale: v2.snapshot.scale)
        check("尺寸标签显示像素", sizeBadge?.text == "\(Int(px.width)) × \(Int(px.height))", sizeBadge?.text ?? "nil")
        key(v2, 53)
        check("Esc 取消截图", await waitUntil { overlay() == nil })
    }

    static func testAnnotations() async {
        guard let v = await startSession(.screenshot) else { return }
        let b = v.bounds
        let sel = CGRect(x: b.width * 0.2, y: b.height * 0.2, width: b.width * 0.5, height: b.height * 0.55)
        drag(v, from: sel.origin, to: CGPoint(x: sel.maxX, y: sel.maxY))
        let editor = v.debugEditor
        let scale = editor.scale
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: sel.minX + sel.width * x, y: sel.minY + sel.height * y) }
        func annotations() -> [Annotation] { editor.model.document.annotations }

        let tools: [(String, AnnotationKind)] = [("矩形", .rect), ("椭圆", .ellipse), ("箭头", .arrow), ("画笔", .pen), ("高亮", .highlight)]
        for (i, (tip, kind)) in tools.enumerated() {
            press(v, tip: tip)
            let y = 0.08 + CGFloat(i) * 0.08
            drag(v, from: p(0.05, y), to: p(0.25, y + 0.06))
            check("\(tip)：拖拽绘制", annotations().last?.kind == kind && annotations().count == i + 1, "\(annotations().map(\.kind))")
        }
        check("二级工具栏：粗细 + 7 色", descendants(of: v, SizeDot.self).filter { !$0.isHiddenOrHasHiddenAncestor }.count == 3
              && descendants(of: v, ColorSwatch.self).filter { !$0.isHiddenOrHasHiddenAncestor }.count == 7)

        press(v, tip: "矩形")
        drag(v, from: p(0.3, 0.1), to: p(0.4, 0.14), flags: .shift)
        let square = annotations().last?.spanRect ?? .zero
        check("⇧ 画正方形", abs(square.width - square.height) < 0.5, "\(square)")

        if let blue = descendants(of: v, ColorSwatch.self).first(where: { $0.color == .blue && !$0.isHiddenOrHasHiddenAncestor }) {
            clickView(blue)
        }
        if let large = descendants(of: v, SizeDot.self).filter({ !$0.isHiddenOrHasHiddenAncestor }).last {
            clickView(large)
        }
        drag(v, from: p(0.3, 0.2), to: p(0.45, 0.3))
        check("选颜色和粗细后绘制", annotations().last?.style.color == .blue && annotations().last?.style.lineWidth == 8 * scale,
              "\(String(describing: annotations().last?.style))")

        press(v, tip: "马赛克")
        press(v, tip: "框选马赛克")
        drag(v, from: p(0.5, 0.05), to: p(0.7, 0.2))
        check("框选马赛克", annotations().last?.kind == .mosaicBox)
        press(v, tip: "画笔马赛克")
        drag(v, from: p(0.5, 0.25), to: p(0.7, 0.3))
        check("画笔马赛克", annotations().last?.kind == .mosaicBrush)

        press(v, tip: "文本")
        let textAt = p(0.5, 0.45)
        click(v, textAt)
        let input = v.window?.firstResponder as? NSTextView
        check("文本：点击出现输入框", input != nil)
        type(v, "Hello")
        input?.insertText("中文", replacementRange: NSRange(location: NSNotFound, length: 0)) // stands in for an IME commit
        key(v, 53) // Esc ends editing
        check("文本：输入英文和中文", annotations().last?.kind == .text && annotations().last?.text == "Hello中文", annotations().last?.text ?? "nil")
        check("文本：Esc 结束输入后截图仍在", overlay() != nil)

        press(v, tip: "标签")
        let labelAt = p(0.5, 0.65)
        click(v, labelAt)
        (v.window?.firstResponder as? NSTextView)?.insertText("说明", replacementRange: NSRange(location: NSNotFound, length: 0))
        key(v, 53)
        check("标签：点击放置并输入", annotations().last?.kind == .label && annotations().last?.text == "说明")
        click(v, labelAt)
        check("标签：点击定位点翻转方向", annotations().last?.labelFlipped == true)

        press(v, tip: "矩形")
        let textBox = annotations().first { $0.kind == .text }!.bounds
        click(v, CGPoint(x: (textBox.minX + 4) / scale, y: (textBox.midY) / scale), count: 2)
        let editing = v.window?.firstResponder as? NSTextView
        check("双击文本重新编辑（预填原文）", editing?.string == "Hello中文", editing?.string ?? "nil")
        editing?.insertText("改", replacementRange: editing?.selectedRange() ?? NSRange(location: 0, length: 0))
        key(v, 53)
        check("编辑后文本更新", annotations().contains { $0.kind == .text && $0.text == "改" })

        let countBeforeUndo = annotations().count
        press(v, tip: "撤销")
        check("撤销按钮", annotations().contains { $0.kind == .text && $0.text == "Hello中文" })
        key(v, 6, chars: "z", flags: .command)
        check("⌘Z 撤销", annotations().allSatisfy { !($0.kind == .label && $0.labelFlipped) })
        key(v, 6, chars: "Z", flags: [.command, .shift])
        key(v, 6, chars: "Z", flags: [.command, .shift])
        check("⇧⌘Z 重做", annotations().contains { $0.kind == .text && $0.text == "改" } && annotations().count == countBeforeUndo)

        press(v, tip: "矩形") // toggle the tool off
        check("再次点击工具取消选择", editor.tool == nil)
        let rect = annotations().first { $0.kind == .rect }!
        click(v, CGPoint(x: rect.spanRect.minX / scale, y: rect.spanRect.midY / scale))
        check("无工具时点击选中标注", editor.model.selectedID == rect.id)
        let count = annotations().count
        key(v, 51)
        check("Delete 删除选中标注", annotations().count == count - 1 && !annotations().contains { $0.id == rect.id })

        press(v, tip: "水印")
        if let field = descendants(of: v, WatermarkPanel.self).first.flatMap({ descendants(of: $0, NSTextField.self).first { $0.isEditable } }) {
            field.stringValue = "机密"
            NotificationCenter.default.post(name: NSControl.textDidChangeNotification, object: field)
        }
        press(v, title: "确定")
        check("水印：输入文字后确定", editor.model.document.watermark?.text == "机密")

        let selNow = v.selection ?? .zero
        let expectedPx = CoordinateSpace.pixelRect(fromPoints: selNow, scale: scale)
        let plain = Compositor.crop(v.snapshot.image, to: expectedPx)
        key(v, 36) // Return copies
        check("回车保存到剪切板并结束", await waitUntil { overlay() == nil })
        let copied = pasteboardImage()
        check("剪切板图片尺寸 = 选区像素", copied.map { CGSize(width: $0.width, height: $0.height) } == expectedPx.size,
              "\(String(describing: copied.map { ($0.width, $0.height) })) vs \(expectedPx.size)")
        check("导出图包含标注（与原图不同）", copied.flatMap(ImageEncoder.png) != plain.flatMap(ImageEncoder.png))
    }

    static func testOutputs() async {
        let b = NSScreen.main?.frame.size ?? .zero
        let win = CGRect(x: b.width * 0.1, y: b.height * 0.1, width: b.width * 0.4, height: b.height * 0.5)

        guard let v = await startSession(.screenshot) else { return }
        click(v, CGPoint(x: win.midX, y: win.midY))
        click(v, CGPoint(x: win.midX, y: win.midY), count: 2)
        check("双击选区保存到剪切板", await waitUntil { overlay() == nil })
        let px = CoordinateSpace.pixelRect(fromPoints: win, scale: v.snapshot.scale)
        check("双击复制的尺寸", pasteboardImage().map { CGSize(width: $0.width, height: $0.height) } == px.size)

        guard let v2 = await startSession(.screenshot) else { return }
        click(v2, CGPoint(x: win.midX, y: win.midY))
        let dir = ProcessInfo.processInfo.environment["RETICLE_E2E_SAVE_DIR"].map { URL(fileURLWithPath: $0) }
        let existing = dir.flatMap { try? FileManager.default.contentsOfDirectory(atPath: $0.path) } ?? []
        press(v2, tip: "下载")
        check("下载保存文件并结束", await waitUntil { overlay() == nil })
        let files = dir.flatMap { try? FileManager.default.contentsOfDirectory(atPath: $0.path) } ?? []
        let newFile = files.first { !existing.contains($0) && $0.hasPrefix("Reticle_") && $0.hasSuffix(".png") }
        check("下载的 PNG 文件存在", newFile != nil, files.joined(separator: ","))

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("sentinel", forType: .string)
        guard let v3 = await startSession(.screenshot) else { return }
        click(v3, CGPoint(x: win.midX, y: win.midY))
        press(v3, tip: "取消")
        check("✕ 取消结束截图", await waitUntil { overlay() == nil })
        check("取消不改动剪切板", NSPasteboard.general.string(forType: .string) == "sentinel")
    }

    static func testPin() async {
        guard let v = await startSession(.screenshot) else { return }
        let b = v.bounds
        let win = CGRect(x: b.width * 0.1, y: b.height * 0.1, width: b.width * 0.4, height: b.height * 0.5)
        click(v, CGPoint(x: win.midX, y: win.midY))
        let expected = v.selectionGlobalFrame
        press(v, tip: "固定到屏幕")
        check("固定到屏幕：结束截图", await waitUntil { overlay() == nil })
        let pin = NSApp.windows.compactMap { $0 as? PinWindow }.first { $0.isVisible }
        check("贴图窗口出现在原位置（误差 < 1pt）", pin.map { p in expected.map { abs(p.frame.minX - $0.minX) < 1 && abs(p.frame.minY - $0.minY) < 1 && abs(p.frame.width - $0.width) < 1 } ?? false } == true,
              "\(String(describing: pin?.frame)) vs \(String(describing: expected))")
        check("贴图 1:1 像素显示", pin.map { $0.frame.width * 2 == CGFloat($0.image.width) } == true,
              "frame=\(String(describing: pin?.frame.size)) image=\(String(describing: pin.map { ($0.image.width, $0.image.height) }))")
        check("贴图浮在最上层、所有桌面可见", pin?.level == .floating && pin?.collectionBehavior.contains(.canJoinAllSpaces) == true)
        if let pin, let content = pin.contentView {
            let right = NSEvent.mouseEvent(with: .rightMouseDown, location: CGPoint(x: 10, y: 10), modifierFlags: [], timestamp: 0,
                                           windowNumber: pin.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            let menu = content.menu(for: right)
            check("贴图右键菜单：复制/保存…/关闭", menu?.items.map(\.title) == ["复制", "保存…", "关闭"])
            pin.copyImage()
            check("贴图右键复制", pasteboardImage()?.width == pin.image.width)
            click(content, CGPoint(x: content.bounds.midX, y: content.bounds.midY), count: 2)
            check("双击关闭贴图", await waitUntil { !pin.isVisible })
        }
    }

    static func testTextRecognition() async {
        guard let v = await startSession(.screenshot) else { return }
        press(v, title: "提取文字")
        check("模式栏切换到提取文字", AppDelegateAccess.session?.mode == .recognizeText)
        let b = v.bounds
        let textRegion = CGRect(x: b.width * 0.28, y: b.height * 0.40, width: b.width * 0.30, height: b.height * 0.14)
        drag(v, from: textRegion.origin, to: CGPoint(x: textRegion.maxX, y: textRegion.maxY))
        let recognized = await waitUntil(timeout: 15) { panelText(v)?.contains("Reticle demo") == true }
        check("框选后自动识别文字", recognized, panelText(v) ?? "nil")
        check("提取文字模式不显示截图工具栏", visibleButton(in: v, tip: "保存到剪切板") == nil)
        press(v, title: "复制")
        check("复制全文", NSPasteboard.general.string(forType: .string)?.contains("Reticle demo") == true)

        if #available(macOS 15, *) {
            press(v, title: "翻译")
            // Installed language data → translation; otherwise explicit download guidance (never a silent hang).
            let settled = await waitUntil(timeout: 15) { visibleButton(in: v, title: "原文") != nil || visibleButton(in: v, title: "去下载") != nil }
            let translated = visibleButton(in: v, title: "原文") != nil
            check("翻译：返回译文，或未下载语言包时提示“去下载”", settled, panelStatus(v) ?? "")
            notes.append(translated ? "翻译结果：\(panelText(v) ?? "")" : "翻译：本机未下载语言包，显示“\(panelStatus(v) ?? "")”")
        }

        press(v, tip: "关闭")
        check("关闭面板后重新框选", v.selection == nil && descendants(of: v, TextRecognitionPanel.self).isEmpty)
        key(v, 53)
        _ = await waitUntil { overlay() == nil }

        guard let v2 = await startSession(.screenshot) else { return }
        press(v2, title: "截图")
        drag(v2, from: textRegion.origin, to: CGPoint(x: textRegion.maxX, y: textRegion.maxY))
        press(v2, tip: "提取文字")
        check("工具栏入口提取文字", await waitUntil(timeout: 15) { panelText(v2)?.contains("Reticle demo") == true }, panelText(v2) ?? "nil")
        notes.append("提取文字后主进程内存 \(footprintMB()) MB（Vision 在 ReticleWorker 中，识别完即退出）")
    }

    static func testScrollCapture() async {
        guard let v = await startSession(.screenshot) else { return }
        press(v, title: "滚动截图")
        let b = v.bounds
        drag(v, from: CGPoint(x: b.width * 0.3, y: b.height * 0.2), to: CGPoint(x: b.width * 0.6, y: b.height * 0.7))
        check("滚动截图：框选后显示提示和开始按钮", visibleButton(in: v, title: "开始滚动截图") != nil
              && descendants(of: v, NSTextField.self).contains { $0.stringValue.contains("只框选会滚动的内容") && !$0.isHiddenOrHasHiddenAncestor })
        check("滚动截图模式不显示截图工具栏", visibleButton(in: v, tip: "保存到剪切板") == nil)
        press(v, title: "开始滚动截图")
        check("开始后关闭冻结遮罩", await waitUntil { overlay() == nil })
        let panel = await waitFor { NSApp.windows.compactMap { $0 as? ScrollControlPanel }.first { $0.isVisible } }
        check("出现滚动截图控制面板", panel != nil)
        let frame = NSApp.windows.first { $0.ignoresMouseEvents && $0.level == .screenSaver && $0.isVisible }
        check("选区边框窗口可被鼠标穿透", frame != nil)
        if let panel {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            let status = descendants(of: panel.contentView!, NSTextField.self).map(\.stringValue).joined(separator: " ")
            notes.append("滚动截图控制面板状态（无屏幕录制权限时预期为报错）：\(status)")
            check("控制面板按钮：自动滚动/完成/取消", ["自动滚动", "完成", "取消"].allSatisfy { visibleButton(in: panel.contentView!, title: $0) != nil })
            press(panel.contentView!, title: "取消")
            check("取消后关闭控制面板和边框", await waitUntil { !panel.isVisible && frame?.isVisible != true })
        }

        // Stitching with real capture needs permission; exercise the stitcher on a synthetic scroll instead.
        let page = RenderFixtures.tallPage(width: 400, height: 1600)
        let stitcher = ScrollStitcher()
        for y in [0, 90, 260, 500, 700, 600, 900] { _ = stitcher.add(page.cropping(to: CGRect(x: 0, y: y, width: 400, height: 500))!) }
        check("拼接器：模拟滚动得到 0…1400 的长图", stitcher.compose()?.height == 1400)
    }

    static func testLongImageWindow() async {
        let page = RenderFixtures.tallPage(width: 1200, height: 2400)
        LongImageWindow.show(image: page, scale: 2)
        guard let w = await waitFor({ NSApp.windows.compactMap { $0 as? LongImageWindow }.first { $0.isVisible } }), let content = w.contentView else {
            check("长图窗口打开", false)
            return
        }
        check("长图窗口：编辑/保存/取消/保存到剪切板", ["编辑", "保存", "取消", "保存到剪切板"].allSatisfy { visibleButton(in: content, tip: $0) != nil })
        press(content, tip: "编辑")
        check("点编辑出现标注工具栏（无固定/提取文字/滚动截图）",
              visibleButton(in: content, tip: "矩形") != nil && visibleButton(in: content, tip: "固定到屏幕") == nil)
        guard let doc = descendants(of: content, LongImageDocumentView.self).first else { return }
        press(content, tip: "矩形")
        drag(doc, from: CGPoint(x: 40, y: 40), to: CGPoint(x: 200, y: 140))
        check("长图上绘制矩形", doc.editor.model.document.annotations.count == 1,
              "count=\(doc.editor.model.document.annotations.count) tool=\(String(describing: doc.editor.tool)) hit=\(String(describing: content.window?.contentView?.hitTest(doc.convert(CGPoint(x: 40, y: 40), to: nil))))")
        press(content, tip: "下载")
        check("下载弹出保存面板", await waitUntil { w.attachedSheet != nil })
        if let sheet = w.attachedSheet { w.endSheet(sheet, returnCode: .cancel) }
        _ = await waitUntil { w.attachedSheet == nil }
        press(content, tip: "保存到剪切板")
        check("长图保存到剪切板（原尺寸）", pasteboardImage().map { CGSize(width: $0.width, height: $0.height) } == CGSize(width: 1200, height: 2400))
        check("保存到剪切板后关闭窗口", await waitUntil { !w.isVisible })
    }

    static func testRecording() async {
        guard let v = await startSession(.record) else { return }
        check("录屏模式不显示顶部模式栏", visibleButton(in: v, title: "滚动截图") == nil)
        let b = v.bounds
        drag(v, from: CGPoint(x: b.width * 0.3, y: b.height * 0.3), to: CGPoint(x: b.width * 0.6, y: b.height * 0.6))
        let segmented = descendants(of: v, NSSegmentedControl.self).first { !$0.isHiddenOrHasHiddenAncestor }
        check("录屏：MP4/GIF 选择（默认 MP4）+ 开始录制", segmented?.selectedSegment == 0 && segmented?.label(forSegment: 1) == "GIF"
              && visibleButton(in: v, title: "开始录制") != nil,
              "segmented=\(String(describing: segmented?.selectedSegment)) label=\(String(describing: segmented?.label(forSegment: 1))) start=\(visibleButton(in: v, title: "开始录制") != nil) selection=\(String(describing: v.selection)) mode=\(String(describing: AppDelegateAccess.session?.mode))")
        check("录屏模式不能标注", visibleButton(in: v, tip: "矩形") == nil)
        key(v, 53)
        _ = await waitUntil { overlay() == nil }
        notes.append("未执行“开始录制”：真实录制需要屏幕录制权限。")

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("reticle-e2e-\(UUID()).mp4")
        guard await RenderFixtures.writeVideo(to: url, seconds: 3) else {
            check("生成测试视频", false)
            return
        }
        for format in RecordingFormat.allCases {
            NSPasteboard.general.clearContents()
            guard let (process, pipe) = try? WorkerClient.openPreview(url: url, format: format, environment: ["RETICLE_WORKER_SELFTEST": "1"]) else {
                check("\(format.rawValue)：启动 ReticleWorker", false)
                continue
            }
            // The preview runs in ReticleWorker; its self-test reports checks on stdout.
            let output = await readToEnd(pipe, of: process, timeout: 60)
            for line in output.split(separator: "\n") where line.hasPrefix("✓ ") || line.hasPrefix("✗ ") {
                check("worker · " + line.dropFirst(2), line.hasPrefix("✓"))
            }
            check("\(format.rawValue)：worker 完成后退出", !process.isRunning)
            let copied = (NSPasteboard.general.readObjects(forClasses: [NSURL.self]) as? [URL])?.first { $0.pathExtension == format.fileExtension }
            check("\(format.rawValue)：剪贴板里是导出的文件", copied.map { FileManager.default.fileExists(atPath: $0.path) } == true, copied?.path ?? "nil")
            if format == .gif, let copied, let src = CGImageSourceCreateWithURL(copied as CFURL, nil) {
                check("GIF 帧数≈时长×10", CGImageSourceGetCount(src) >= 25, "\(CGImageSourceGetCount(src))")
            }
        }
        notes.append("录屏预览/导出后主进程内存 \(footprintMB()) MB（AVFoundation 在 worker 中，已随进程退出）")
        try? FileManager.default.removeItem(at: url)
    }

    static func testSettings() async {
        guard let delegate = NSApp.delegate as? AppDelegate else { return }
        let captureOK = delegate.registerHotkey(.capture)
        let recordOK = delegate.registerHotkey(.record)
        check("注册 ⇧⌘A / ⌥⇧R", captureOK && recordOK, "capture=\(captureOK) record=\(recordOK)（false 表示被其他应用占用）")

        delegate.debugShowSettings()
        guard let w = await waitFor({ NSApp.windows.first { $0.title == "Reticle 设置" && $0.isVisible } }), let content = w.contentView else {
            check("打开设置窗口", false)
            return
        }
        try? await Task.sleep(nanoseconds: 500_000_000)
        let recorders = descendants(of: content, RecorderButton.self)
        check("设置页：截图、录屏两个快捷键", recorders.map(\.title) == ["⇧⌘A", "⌥⇧R"], recorders.map(\.title).joined(separator: ","))
        if let first = recorders.first {
            first.performClick(nil)
            check("点击后进入录制", first.title == "请按下快捷键…")
            key(first, 40, chars: "k", flags: [.control, .option])
            let target = HotkeyCombo(keyCode: 40, modifiers: [.control, .option])
            check("录入新快捷键 ⌃⌥K 并保存", await waitUntil { Preferences.captureHotkey == target }, Preferences.captureHotkey.displayString)
            check("按钮显示新快捷键", first.title == "⌃⌥K", first.title)
        }
        Preferences.captureHotkey = .defaultCapture
        delegate.registerHotkey(.capture)
        w.close()
    }

    static func testHistory() async {
        guard ProcessInfo.processInfo.environment["RETICLE_HISTORY_DIR"] != nil else {
            notes.append("未设置 RETICLE_HISTORY_DIR，跳过截图历史测试（避免写入真实历史）")
            return
        }
        let history = ScreenshotHistory.shared
        let wasEnabled = Preferences.historyEnabled
        Preferences.historyEnabled = true
        defer { Preferences.historyEnabled = wasEnabled }
        history.clear()
        history.flush()
        _ = await waitUntil { history.entries.isEmpty }

        guard let v = await startSession(.screenshot) else { return }
        let b = v.bounds
        let win = CGRect(x: b.width * 0.1, y: b.height * 0.1, width: b.width * 0.4, height: b.height * 0.5)
        click(v, CGPoint(x: win.midX, y: win.midY))
        let px = CoordinateSpace.pixelRect(fromPoints: win, scale: v.snapshot.scale)
        key(v, 36)
        _ = await waitUntil { overlay() == nil }
        history.flush()
        check("复制后记入历史", await waitUntil { history.entries.count == 1 }, "\(history.entries.count)")
        check("历史记录尺寸 = 截图像素", history.entries.first.map { CGSize(width: $0.pixelWidth, height: $0.pixelHeight) } == px.size)
        check("历史图片文件存在", history.entries.first.map { FileManager.default.fileExists(atPath: history.imageURL(for: $0).path) } == true)

        guard let menu = (NSApp.delegate as? AppDelegate)?.debugHistoryMenu else {
            check("菜单栏有“最近截图”", false)
            return
        }
        menu.menuNeedsUpdate(menu)
        let rows = menu.items.filter { $0.representedObject is UUID && !$0.isAlternate }
        check("最近截图菜单：一行带缩略图和尺寸", rows.count == 1 && rows[0].image != nil && rows[0].title.contains("\(Int(px.width)) × \(Int(px.height))"),
              rows.map(\.title).joined(separator: ","))
        check("按住 ⌥ 显示“用预览打开”", menu.items.contains { $0.isAlternate && $0.title.hasPrefix("用预览打开") })
        check("菜单底部：在访达中显示 / 清空历史", menu.items.contains { $0.title == "在访达中显示" } && menu.items.contains { $0.title == "清空历史…" && $0.isEnabled })

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("sentinel", forType: .string)
        if let row = rows.first { menu.copyEntry(row) }
        check("点击历史重新复制", pasteboardImage().map { CGSize(width: $0.width, height: $0.height) } == px.size)
        menu.menuDidClose(menu)
        try? await Task.sleep(nanoseconds: 100_000_000)
        check("关闭菜单后释放缩略图", !menu.items.contains { $0.image != nil })

        guard let v2 = await startSession(.screenshot) else { return }
        drag(v2, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 260))
        press(v2, tip: "固定到屏幕")
        _ = await waitUntil { overlay() == nil }
        history.flush()
        check("固定到屏幕也记入历史，最新在前", await waitUntil { history.entries.count == 2 } && history.entries.first?.pixelWidth == 400)
        NSApp.windows.compactMap { $0 as? PinWindow }.forEach { $0.dismiss() }

        Preferences.historyEnabled = false
        guard let v3 = await startSession(.screenshot) else { return }
        click(v3, CGPoint(x: win.midX, y: win.midY))
        key(v3, 36)
        _ = await waitUntil { overlay() == nil }
        history.flush()
        try? await Task.sleep(nanoseconds: 300_000_000)
        check("关闭“保存截图历史”后不再记录", history.entries.count == 2)
        Preferences.historyEnabled = true

        history.clear()
        history.flush()
        check("清空历史", await waitUntil { history.entries.isEmpty }
              && ((try? FileManager.default.contentsOfDirectory(atPath: history.directory.path)) ?? []) == ["index.json"])
    }

    /// AppKit global frame of the helper window (see scripts/e2e-scroll-target.swift).
    static let helperFrame = CGRect(x: 160, y: 120, width: 520, height: 560)

    /// Uses the live screen instead of the demo image, with a helper app that shows and scrolls a tall page.
    /// The helper must be a separate app: captures exclude Reticle's own windows by app.
    static func testRealScreen() async {
        guard CGPreflightScreenCaptureAccess() else {
            notes.append("没有屏幕录制权限，跳过真实屏幕测试")
            return
        }
        let demo = ProcessInfo.processInfo.environment["RETICLE_DEMO_IMAGE"]
        unsetenv("RETICLE_DEMO_IMAGE")
        defer { if let demo { setenv("RETICLE_DEMO_IMAGE", demo, 1) } }
        let saveDir = ProcessInfo.processInfo.environment["RETICLE_E2E_SAVE_DIR"].map { URL(fileURLWithPath: $0) }

        guard ProcessInfo.processInfo.environment["RETICLE_E2E_HELPER"] != nil else {
            notes.append("未设置 RETICLE_E2E_HELPER，跳过真实屏幕测试（用 scripts/e2e.sh 运行）")
            return
        }
        // 1. Real screenshot with window snapping onto the helper window.
        var helper = launchHelper(delay: 30, seconds: 0)
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        guard let v = await startSession(.screenshot) else { helper?.terminate(); return }
        let screen = v.snapshot.screen
        check("真实截屏：图像为屏幕像素尺寸", v.snapshot.image.width == Int(screen.frame.width * screen.backingScaleFactor),
              "\(v.snapshot.image.width) vs \(screen.frame.width * screen.backingScaleFactor)")
        check("真实截屏：读取到窗口列表", !v.snapshot.windows.isEmpty, "\(v.snapshot.windows.count)")
        let local = CGRect(x: helperFrame.minX - screen.frame.minX, y: screen.frame.maxY - helperFrame.maxY,
                           width: helperFrame.width, height: helperFrame.height)
        click(v, CGPoint(x: local.midX, y: local.midY))
        check("真实截屏：单击吸附到置顶窗口", approx(v.selection, local), "\(String(describing: v.selection)) vs \(local)")
        key(v, 36)
        _ = await waitUntil { overlay() == nil }
        let shot = pasteboardImage()
        check("真实截屏：复制的尺寸", shot.map { CGSize(width: $0.width, height: $0.height) } == CoordinateSpace.pixelRect(fromPoints: local, scale: screen.backingScaleFactor).size)
        // The helper page is white with gray bars; the capture must show it (not whatever is behind).
        check("真实截屏：截到的是辅助窗口的内容", shot.map { averageGray($0) > 150 } == true, "平均灰度 \(shot.map { averageGray($0) } ?? -1)")
        if let shot, let saveDir { try? ImageEncoder.png(shot)?.write(to: saveDir.appendingPathComponent("real-screenshot.png")) }
        helper?.terminate()

        // 2. Scroll capture while the helper scrolls (manual scrolling stand-in).
        helper = launchHelper(delay: 3.5, seconds: 7)
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        guard let v2 = await startSession(.screenshot) else { helper?.terminate(); return }
        press(v2, title: "滚动截图")
        let region = local.insetBy(dx: 20, dy: 20)
        drag(v2, from: region.origin, to: CGPoint(x: region.maxX, y: region.maxY))
        press(v2, title: "开始滚动截图")
        let panel = await waitFor { NSApp.windows.compactMap { $0 as? ScrollControlPanel }.first { $0.isVisible } }
        check("真实滚动截图：开始采集", panel != nil)
        var statuses = Set<String>()
        let until = Date().addingTimeInterval(11)
        while Date() < until, let panel {
            statuses.formUnion(descendants(of: panel.contentView!, NSTextField.self).map(\.stringValue).filter { !$0.isEmpty })
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        notes.append("滚动截图状态：\(statuses.sorted().suffix(4).joined(separator: " / "))")
        if let panel { press(panel.contentView!, title: "完成") }
        let long = await waitFor(timeout: 10) { NSApp.windows.compactMap { $0 as? LongImageWindow }.first { $0.isVisible } }
        check("真实滚动截图：完成后打开长图窗口", long != nil)
        if let long, let content = long.contentView {
            press(content, tip: "保存到剪切板")
            let image = pasteboardImage()
            let regionPx = CoordinateSpace.pixelRect(fromPoints: region, scale: screen.backingScaleFactor)
            // 7 s at ~180 pt/s ≈ 1260 pt ≈ 2520 px of new content on a 2× screen.
            check("真实滚动截图：长图明显长于选区", (image?.height ?? 0) > Int(regionPx.height) + 1500,
                  "长图 \(image?.height ?? 0) px，选区 \(Int(regionPx.height)) px")
            check("真实滚动截图：宽度 = 选区宽度", image?.width == Int(regionPx.width))
            if let image, let saveDir { try? ImageEncoder.png(image)?.write(to: saveDir.appendingPathComponent("real-scroll.png")) }
        }
        helper?.terminate()

        // 3. Record ~3 s of the scrolling helper.
        helper = launchHelper(delay: 0.5, seconds: 8)
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        guard let v3 = await startSession(.record) else { helper?.terminate(); return }
        drag(v3, from: region.origin, to: CGPoint(x: region.maxX, y: region.maxY))
        // The worker inherits these: stop after 3 s, then self-test the preview (copies the MP4 and exits).
        setenv("RETICLE_WORKER_AUTOSTOP", "3", 1)
        setenv("RETICLE_WORKER_SELFTEST", "1", 1)
        NSPasteboard.general.clearContents()
        press(v3, title: "开始录制")
        unsetenv("RETICLE_WORKER_AUTOSTOP")
        unsetenv("RETICLE_WORKER_SELFTEST")
        let worker = await waitFor { WorkerClient.recordingProcess }
        check("真实录屏：交给 ReticleWorker 录制", worker != nil)
        check("真实录屏：worker 录完、预览、导出后退出", await waitUntil(timeout: 40) { WorkerClient.recordingProcess == nil })
        let file = (NSPasteboard.general.readObjects(forClasses: [NSURL.self]) as? [URL])?.first { $0.pathExtension == "mp4" }
        if let file {
            let asset = AVURLAsset(url: file)
            let seconds = (try? await asset.load(.duration)).map(CMTimeGetSeconds) ?? 0
            let size = try? await asset.loadTracks(withMediaType: .video).first?.load(.naturalSize)
            let expected = RecordingLimits.evenPixelSize(CGSize(width: region.width * screen.backingScaleFactor, height: region.height * screen.backingScaleFactor))
            check("真实录屏：时长约 3 秒", seconds > 2.3 && seconds < 4.5, "\(seconds) s")
            check("真实录屏：分辨率 = 选区像素（偶数）", size == expected, "\(String(describing: size)) vs \(expected)")
            if let saveDir { try? FileManager.default.copyItem(at: file, to: saveDir.appendingPathComponent("real-recording.mp4")) }
        } else {
            check("真实录屏：导出 MP4 到剪贴板", false)
        }
        helper?.terminate()
    }

    /// Reads a child's stdout until it exits (or the timeout passes).
    private static func readToEnd(_ pipe: Pipe, of process: Process, timeout: TimeInterval) async -> String {
        let data: Data = await withCheckedContinuation { continuation in
            DispatchQueue.global().async { continuation.resume(returning: pipe.fileHandleForReading.readDataToEndOfFile()) }
        }
        _ = await waitUntil(timeout: timeout) { !process.isRunning }
        return String(decoding: data, as: UTF8.self)
    }

    private static func launchHelper(delay: Double, seconds: Double) -> Process? {
        guard let path = ProcessInfo.processInfo.environment["RETICLE_E2E_HELPER"] else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = ["\(helperFrame.minX)", "\(helperFrame.minY)", "\(helperFrame.width)", "\(helperFrame.height)", "\(delay)", "\(seconds)"]
        do { try p.run() } catch { return nil }
        return p
    }

    /// Mean gray level (0–255) of a downscaled copy.
    private static func averageGray(_ image: CGImage) -> Int {
        let ctx = CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 32, space: CGColorSpaceCreateDeviceGray(),
                            bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: 32, height: 32))
        let p = ctx.data!.assumingMemoryBound(to: UInt8.self)
        return (0..<1024).reduce(0) { $0 + Int(p[$1]) } / 1024
    }

    // MARK: - Session helpers

    private static func overlay() -> OverlayView? {
        NSApp.windows.compactMap { $0 as? OverlayWindow }.first { $0.isVisible }?.contentView as? OverlayView
    }

    private static func startSession(_ mode: CaptureMode) async -> OverlayView? {
        await endSessionIfNeeded()
        if overlay() != nil {
            check("上一个截图会话已结束", false)
            return nil
        }
        (NSApp.delegate as? AppDelegate)?.startCapture(mode: mode)
        let v = await waitFor { overlay() }
        try? await Task.sleep(nanoseconds: 300_000_000)
        if v == nil { check("打开截图遮罩（\(mode)）", false) }
        return v
    }

    private static func endSessionIfNeeded() async {
        if let v = overlay() { key(v, 53) }
        _ = await waitUntil { overlay() == nil && AppDelegateAccess.session == nil }
    }

    // MARK: - Event helpers

    private static func mouse(_ view: NSView, _ type: NSEvent.EventType, _ p: CGPoint, count: Int = 1, flags: NSEvent.ModifierFlags = []) {
        guard let w = view.window else { return }
        let wp = view.convert(p, to: nil)
        guard let e = NSEvent.mouseEvent(with: type, location: wp, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                         windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: count, pressure: 1) else { return }
        w.sendEvent(e)
    }

    private static func click(_ view: NSView, _ p: CGPoint, count: Int = 1) {
        if count == 2 {
            mouse(view, .leftMouseDown, p, count: 1)
            mouse(view, .leftMouseUp, p, count: 1)
        }
        mouse(view, .leftMouseDown, p, count: count)
        mouse(view, .leftMouseUp, p, count: count)
    }

    private static func clickView(_ view: NSView) {
        click(view, CGPoint(x: view.bounds.midX, y: view.bounds.midY))
    }

    private static func drag(_ view: NSView, from a: CGPoint, to b: CGPoint, flags: NSEvent.ModifierFlags = []) {
        mouse(view, .leftMouseDown, a, flags: flags)
        for i in 1...10 {
            let t = CGFloat(i) / 10
            mouse(view, .leftMouseDragged, CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t), flags: flags)
        }
        mouse(view, .leftMouseUp, b, flags: flags)
    }

    /// Characters a real keyboard sends for special keys; text views interpret by character.
    private static let specialKeyChars: [UInt16: String] = [
        53: "\u{1b}", 36: "\r", 76: "\u{3}", 51: "\u{7f}",
        117: String(UnicodeScalar(NSDeleteFunctionKey)!), 123: String(UnicodeScalar(NSLeftArrowFunctionKey)!),
        124: String(UnicodeScalar(NSRightArrowFunctionKey)!), 125: String(UnicodeScalar(NSDownArrowFunctionKey)!),
        126: String(UnicodeScalar(NSUpArrowFunctionKey)!),
    ]

    private static func key(_ view: NSView, _ code: UInt16, chars: String = "", flags: NSEvent.ModifierFlags = []) {
        guard let w = view.window else { return }
        let chars = chars.isEmpty ? (specialKeyChars[code] ?? "") : chars
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            if let e = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                        windowNumber: w.windowNumber, context: nil, characters: chars, charactersIgnoringModifiers: chars.lowercased(),
                                        isARepeat: false, keyCode: code) {
                w.sendEvent(e)
            }
        }
    }

    private static func type(_ view: NSView, _ text: String) {
        for c in text { key(view, 0, chars: String(c)) }
    }

    /// Clicks a button found by tooltip or title (buttons track the mouse modally, so use performClick).
    private static func press(_ root: NSView, tip: String? = nil, title: String? = nil) {
        let button = tip.flatMap { visibleButton(in: root, tip: $0) } ?? title.flatMap { visibleButton(in: root, title: $0) }
        guard let button else {
            check("找到按钮 \(tip ?? title ?? "")", false)
            return
        }
        button.performClick(nil)
    }

    private static func visibleButton(in root: NSView, tip: String) -> NSButton? {
        descendants(of: root, NSButton.self).first { $0.toolTip == tip && !$0.isHiddenOrHasHiddenAncestor }
    }

    private static func visibleButton(in root: NSView, title: String) -> NSButton? {
        descendants(of: root, NSButton.self).first { $0.title == title && !$0.isHiddenOrHasHiddenAncestor }
    }

    private static func descendants<T: NSView>(of root: NSView, _ type: T.Type) -> [T] {
        var found: [T] = []
        var stack: [NSView] = [root]
        while let v = stack.popLast() {
            if let t = v as? T { found.append(t) }
            stack.append(contentsOf: v.subviews.reversed())
        }
        return found
    }

    private static func panelText(_ v: OverlayView) -> String? {
        descendants(of: v, TextRecognitionPanel.self).first.flatMap { descendants(of: $0, NSTextView.self).first?.string }
    }

    private static func panelStatus(_ v: OverlayView) -> String? {
        descendants(of: v, TextRecognitionPanel.self).first.map { descendants(of: $0, NSTextField.self).map(\.stringValue).joined(separator: " ") }
    }

    // MARK: - Waiting and checking

    private static func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return condition()
    }

    private static func waitFor<T>(timeout: TimeInterval = 5, _ value: () -> T?) async -> T? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let v = value() { return v }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return value()
    }

    private static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        results.append((name, ok, detail))
        print("\(ok ? "✓" : "✗") \(name)\(ok || detail.isEmpty ? "" : " — \(detail)")")
    }

    private static func approx(_ a: CGRect?, _ b: CGRect) -> Bool {
        guard let a else { return false }
        return abs(a.minX - b.minX) < 0.01 && abs(a.minY - b.minY) < 0.01 && abs(a.width - b.width) < 0.01 && abs(a.height - b.height) < 0.01
    }

    private static func approx(_ a: CGSize?, _ b: CGSize) -> Bool {
        approx(a.map { CGRect(origin: .zero, size: $0) }, CGRect(origin: .zero, size: b))
    }

    private static func approx(_ a: CGPoint?, _ b: CGPoint) -> Bool {
        approx(a.map { CGRect(origin: $0, size: .zero) }, CGRect(origin: b, size: .zero))
    }

    private static func pasteboardImage() -> CGImage? {
        guard let data = NSPasteboard.general.data(forType: .png), let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    private static func footprintMB() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return kr == KERN_SUCCESS ? Int(info.phys_footprint / 1_048_576) : -1
    }
}

@MainActor
enum AppDelegateAccess {
    static var session: CaptureSession? { (NSApp.delegate as? AppDelegate)?.debugSession }
}

/// Saves and restores the user's clipboard around the test run.
@MainActor
struct PasteboardBackup {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init() {
        items = (NSPasteboard.general.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { t in item.data(forType: t).map { (t, $0) } })
        }
    }

    func restore() {
        let pb = NSPasteboard.general
        pb.clearContents()
        let restored = items.map { entries -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (t, d) in entries { item.setData(d, forType: t) }
            return item
        }
        if !restored.isEmpty { pb.writeObjects(restored) }
    }
}

enum RenderFixtures {
    /// Tall page of text-like bars, for stitching and long-image tests.
    static func tallPage(width: Int, height: Int) -> CGImage {
        var seed: UInt64 = 7
        func next() -> UInt64 {
            seed &+= 0x9E37_79B9_7F4A_7C15
            var z = seed
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            return z ^ (z >> 27)
        }
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        var y = 0
        while y < height {
            let lh = 6 + Int(next() % 10)
            var x = 8
            while x < width - 8 {
                let w = 4 + Int(next() % 40)
                ctx.setFillColor(CGColor(gray: CGFloat(next() % 200) / 255, alpha: 1))
                ctx.fill(CGRect(x: x, y: height - y - lh, width: min(w, width - 8 - x), height: lh))
                x += w + 3 + Int(next() % 6)
            }
            y += lh + 4 + Int(next() % 8)
        }
        return ctx.makeImage()!
    }

    /// A short H.264 clip with a moving square, standing in for a raw recording.
    static func writeVideo(to url: URL, seconds: Int) async -> Bool {
        let w = 1210, h = 688
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { return false }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: w, AVVideoHeightKey: h])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: w, kCVPixelBufferHeightKey as String: h,
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        for i in 0..<(seconds * 30) {
            while !input.isReadyForMoreMediaData { try? await Task.sleep(nanoseconds: 2_000_000) }
            var pb: CVPixelBuffer?
            guard let pool = adaptor.pixelBufferPool else { return false }
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb)
            guard let pb else { return false }
            CVPixelBufferLockBaseAddress(pb, [])
            if let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb), width: w, height: h, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
                                   space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
                ctx.setFillColor(CGColor(gray: 0.95, alpha: 1))
                ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
                ctx.setFillColor(CGColor(red: 0.2, green: 0.44, blue: 1, alpha: 1))
                ctx.fill(CGRect(x: i * 8 % w, y: 300, width: 120, height: 120))
            }
            CVPixelBufferUnlockBaseAddress(pb, [])
            adaptor.append(pb, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: 30))
        }
        input.markAsFinished()
        await writer.finishWriting()
        return writer.status == .completed
    }
}
#endif
