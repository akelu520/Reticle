# M4 滚动截图 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 设计文档 4.6：框选 → 开始滚动截图 → 手动/自动滚动 → 实时拼接 → 编辑/保存/取消/保存到剪切板。

**Architecture:** 拼接算法为 ReticleCore 纯函数（逐行 64 块灰度特征，粗搜 4 行步长 + ±4 精搜）；App 层 `ScrollCaptureController` 关闭冻结遮罩，改为鼠标可穿透的选区边框窗口 + 控制面板，`SCStream` 15 fps 抓取选区，`ScrollFrameSink` 在后台队列喂拼接器；结果交给 `LongImageWindow`。标注编辑抽出为 `AnnotationEditor`，截图遮罩与长图窗口共用。

**Tech Stack:** ScreenCaptureKit (SCStream)、VideoToolbox、CGEvent（自动滚动，需辅助功能权限，`#if !APPSTORE` 隔离）。

---

### Task 1: 拼接算法 ✅
`Stitch/ScrollStitcher.swift`；测试 `ScrollStitcherTests`：向下/向上/回滚、跳变过大判为 mismatch 且能恢复、30000 像素上限、缩略预览；拼接结果与原图逐字节一致。性能：1600×1200 帧 Release 18 ms（Debug 990 ms）。

### Task 2: 编辑器抽取 ✅
`App/Editor/AnnotationEditor.swift`：模型、画布、文字输入、二级工具栏、水印面板；`OverlayView` 改为委托（回归验证：离屏渲染与 M2/M3 一致）。

### Task 3: 滚动采集 ✅
`App/ScrollCapture/{ScrollStartBar,ScrollCaptureController,ScrollFrameSink,ScrollControlPanel}.swift`，`AutoScroll/AutoScroller.swift`
- 入口：模式栏“滚动截图”（框选后显示框选提示 + 开始滚动截图）、主工具栏“滚动截图”（直接开始）
- 控制面板：实时预览、状态（已拼接 N 像素 / 滚动太快）、自动滚动⇄停止滚动、完成、取消
- 自动滚动：首次请求辅助功能权限；把光标移到区域中心，每 50 ms 发 30 px 滚轮事件；1.2 s 无位移自动停止

### Task 4: 结果窗口 ✅
`App/ScrollCapture/LongImageWindow.swift`：可滚动查看长图；底栏 编辑/保存/取消/保存到剪切板；编辑切换为精简工具栏（无固定/提取文字/滚动截图），整张长图可标注。

### 验收记录（2026-09-25）
- `swift test`：51 tests, 0 failures
- 离屏渲染：截图遮罩回归一致；长图窗口编辑态（工具栏、二级工具栏、标注）正确；导出 3024×3928
- Release `.app` 1.2 MB，DMG 812 KB，空闲 11 MB
- 未验证（需真机 + 屏幕录制/辅助功能权限）：SCStream 实时采集、手动/自动滚动拼接效果、控制面板交互
