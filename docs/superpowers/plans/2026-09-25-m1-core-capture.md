# M1 核心截图 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 菜单栏常驻的截图 App：⇧⌘A 冻结全屏 → 窗口识别/框选 → 调整选区 → 复制或下载。

**Architecture:** 纯逻辑（几何、坐标换算、裁剪、编码、快捷键模型）放在本地 Swift Package `ReticleCore` 并用 XCTest 覆盖；App 层用 AppKit：每块屏幕一个 `OverlayWindow` + `OverlayView`，由 `CaptureSession` 统一管理生命周期，会话结束即释放所有位图。

**Tech Stack:** Swift 6.2 编译器（Swift 5 语言模式）、AppKit、Core Animation、ScreenCaptureKit、Carbon Hotkey、SwiftUI（仅设置页）、XcodeGen。

---

### Task 1: ReticleCore 包与几何模型 ✅
**Files:** `Packages/ReticleCore/Package.swift`，`Sources/ReticleCore/Geometry/{SelectionGeometry,WindowPicker,CoordinateSpace}.swift`，测试 `Tests/ReticleCoreTests/{SelectionGeometry,WindowPicker,CoordinateSpace}Tests.swift`
- [x] 写测试：拖拽归一化与夹取、手柄命中（角优先、边全长）、角/边缩放与翻转、移动夹取、工具栏"下→上→内"摆放、窗口前后序拾取与屏幕裁剪、CG 全局 → 屏幕本地翻转坐标（主屏 / 副屏在上方）、点 → 像素外扩取整
- [x] 实现并通过：`swift test --package-path Packages/ReticleCore`

### Task 2: 导出与快捷键模型 ✅
**Files:** `Sources/ReticleCore/Render/Compositor.swift`，`Export/ImageEncoder.swift`，`Hotkey/HotkeyCombo.swift`，测试 `ExportTests.swift`、`HotkeyComboTests.swift`
- [x] 测试：裁剪（左上原点、越界夹取、完全越界返回 nil）、PNG 往返、默认文件名 `Reticle_yyyy-MM-dd_HH-mm-ss.png`、默认快捷键 ⇧⌘A / ⌥⇧R、Carbon 修饰键映射、Codable 往返、必须含 ⌘⌥⌃ 之一
- [x] 实现并通过（19 个测试）

### Task 3: 工程与 App 外壳 ✅
**Files:** `project.yml`，`App/main.swift`，`App/AppDelegate.swift`，`App/Preferences.swift`，`App/StatusBar/StatusBarController.swift`，`App/Hotkey/HotkeyCenter.swift`，`App/Permissions/ScreenCapturePermission.swift`
- [x] LSUIElement 菜单栏 App；菜单：截图 / 设置… / 关于 / 退出
- [x] Carbon 全局快捷键，注册失败时菜单项提示"被占用"；录制新快捷键期间挂起
- [x] 屏幕录制权限预检 + 引导弹窗

### Task 4: 截图会话 ✅
**Files:** `App/Capture/{ScreenGrabber,CaptureSession,OverlayWindow,OverlayView,MagnifierView,CaptureToolbar}.swift`，`App/Output/OutputService.swift`
- [x] `SCScreenshotManager` 并行截取所有屏幕（排除自身），`CGWindowListCopyWindowInfo` 取窗口（layer 0，≥40pt）
- [x] 遮罩：底图用 layer contents；蒙版/边框/手柄放在 layer-hosting 子视图（直接挂在 layer-backed 视图上会被 AppKit 重排，已验证）
- [x] 悬停识别窗口、单击选中、拖拽框选、手柄缩放、拖动移动、方向键微调、尺寸标签、放大镜
- [x] 回车/双击/✓ 复制（PNG+TIFF），↓ 下载（NSSavePanel，取消后回到会话），Esc/✕ 取消，结束后把焦点还给原 App
- [x] DEBUG 钩子：`RETICLE_DEMO_IMAGE`、`RETICLE_AUTOSTART`、`RETICLE_DEBUG_RENDER`（离屏渲染图层树到 PNG 做视觉检查）

### Task 5: 设置页 ✅
**Files:** `App/Settings/{SettingsWindowController,SettingsView,HotkeyRecorder}.swift`
- [x] 快捷键录制（Esc 取消、恢复默认、冲突提示）、开机启动（SMAppService）、默认保存目录；首次打开时才创建 SwiftUI

### Task 6: 打包与 CI ✅
**Files:** `scripts/build-dmg.sh`，`.github/workflows/ci.yml`，`README.md`
- [x] Release 构建 + ad-hoc 签名 + UDZO DMG
- [x] CI：macos-15 上跑单测、打包、上传 artifact；打 `v*` tag 时发布 Release

### 验收记录（2026-09-25，MacBook Pro 3024×1964 Retina）
- `swift test`：19 tests, 0 failures
- Release `.app` 512 KB，DMG 201 KB
- 空闲 phys_footprint 11 MB；演示截图会话中 38 MB（Debug）
- 需人工验证：真实屏幕录制权限下的截图、多显示器、全屏 App 空间
