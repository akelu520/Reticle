# 独立进程（ReticleWorker）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 提取文字与录屏的框架内存（Vision、AVFoundation）不再常驻菜单栏 App。

**Architecture:** App 包内新增命令行目标 `ReticleWorker`（XcodeGen `type: tool`，复制到 `Contents/MacOS`）。主 App 通过 `WorkerClient` 用 `Process` 按任务启动它：OCR 走临时 PNG + stdout JSON；录屏把框选结果（显示器 ID、区域、缩放、格式）以 JSON 参数交给 worker，worker 负责录制到导出的全部界面，最后一个窗口关闭即 `exit(0)`。共享代码放 `Shared/`，协议在 `Shared/WorkerProtocol.swift`。

---

- [x] `Shared/`：Preferences（热键辅助方法留在 App）、RecordingStorage、NSScreen.displayID、WorkerProtocol
- [x] `Worker/`：main（ocr / record / preview）、WorkerApp（无 Dock 图标的 AppKit 宿主、SIGUSR1 结束录制、退出）、Recorder/*（从 App 移入）
- [x] `App/Worker/WorkerClient.swift`：recognizeText、startRecording / stopRecording（再按 ⌥⇧R 结束）
- [x] 调用点：OverlayView 识别文字、CaptureSession 开始录制、AppDelegate（录制中再次 ⌥⇧R、退出时不清理正在预览的原始文件）
- [x] E2E：预览/导出改为 worker 自检（stdout 回报），真实录屏通过环境变量让 worker 3 s 自动结束并自检；检查 worker 退出

### 验收记录（2026-09-25）
- `swift test`：59 tests, 0 failures；`scripts/e2e.sh`：105/105 通过，结束后无残留 worker
- 主进程内存（Debug，单独进程测，用后 3 s）：提取文字 66 MB → 29 MB；录屏预览导出 143 MB → 20 MB；截图+标注+提取文字+录屏 50 MB
- worker 单次 OCR：0.95 s，峰值 RSS 118 MB，退出后全部释放
- Release：`.app` 2.2 MB（ReticleCore 分别静态链接进两个可执行文件），DMG 1.2 MB，空闲 12 MB，`codesign --deep` 校验通过
