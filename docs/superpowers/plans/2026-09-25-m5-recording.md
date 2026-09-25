# M5 录屏 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 设计文档 4.7：⌥⇧R / 菜单 → 框选 → MP4/GIF → 开始录制 → 结束录屏（1 小时上限）→ 剪辑 → 下载 / 复制到剪贴板。

**Architecture:** 纯逻辑（时长格式、偶数像素尺寸、GIF 取帧与尺寸、GIF 写入、临时文件清理）在 ReticleCore；App 层复用截图遮罩的框选（`CaptureMode.record`），`ScreenRecorder` 用 SCStream（30 fps、显示光标、420v）+ `RecordingSink`（AVAssetWriter H.264）录制，`RecordingPreviewWindow` 用 AVPlayerView 自带剪辑界面，`RecordingExporter` 负责 MP4 直通裁剪与 GIF 转码。

**Tech Stack:** ScreenCaptureKit、AVFoundation、AVKit、ImageIO。

---

### Task 1: Core ✅
`Recording/Recording.swift`：`RecordingFormat`、`RecordingLimits`（1 小时、GIF 10 fps / 960 px、偶数尺寸）、`DurationFormat`、`GIFPlan`、`GIFWriter`（流式写入）、`TemporaryFiles.purge`；`FileNaming.name(for:extension:)`。
测试 `RecordingTests`（6 个，含真实 GIF 编码与帧延时校验）。

### Task 2: 快捷键与入口 ✅
`HotkeyCenter.Action.record`、`Preferences.recordHotkey`（默认 ⌥⇧R）、设置页“录屏”行（冲突提示、恢复默认）、菜单栏“录屏”。

### Task 3: 录制 ✅
`App/Recorder/{RecordStartBar,ScreenRecorder,RecordingSink,RecordingStorage}.swift`
- 框选后 MP4/GIF + 取消 + 开始录制（录屏模式不显示顶部模式栏、不可标注）
- 录制中：红色虚线边框（鼠标可穿透）、计时 + 结束录屏；满 1 小时自动结束；静止结尾按当前时间补齐时长
- 原始文件在 Caches/…/Recordings/raw，退出时清理

### Task 4: 预览、剪辑、导出 ✅
`App/Recorder/{RecordingPreviewWindow,RecordingExporter}.swift`：AVPlayerView 播放 + 系统剪辑；下载（保存面板）；复制到剪贴板（导出到 Caches/…/clipboard，写入文件 URL，保留 24 小时）。

### 验收记录（2026-09-25）
- `swift test`：57 tests, 0 failures
- 导出链路（合成 4 s 视频，剪取中间一半）：MP4 2.0 s、1210×688；GIF 20 帧、960×545
- 离屏渲染：录屏模式“MP4 | GIF / 取消 / 开始录制”
- Release `.app` 1.4 MB，DMG 916 KB，空闲 11 MB
- 未验证（需真机 + 屏幕录制权限）：实时录制、计时条、剪辑界面交互、剪贴板粘贴文件
