# M2 标注编辑 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在选区内完成设计文档 4.3 中的全部标注：矩形、椭圆、箭头、画笔、高亮、画笔/框选马赛克、文本、标签，外加撤销和水印。

**Architecture:** 标注数据、编辑状态机、撤销、渲染全部在 ReticleCore（纯 CoreGraphics/CoreText/CoreImage，可单测）；App 层 `OverlayView` 只把鼠标/键盘事件换算成图像像素交给 `EditorModel`，并用 `AnnotationCanvasView`（frame = 选区）调用同一个 `AnnotationRenderer` 绘制，导出走 `Compositor.render`，保证所见即所得。

**Tech Stack:** CoreGraphics、CoreText、CoreImage（CIPixellate）、AppKit。

---

### Task 1: 数据模型 ✅
`Annotation/{RGBA,Annotation,ShapePaths,TextLayout}.swift`：7 色板、9 种标注、样式（像素单位）、命中测试（描边路径放宽容差）、平移、外框、箭头多边形、平滑笔迹、CoreText 测量/绘制、标签布局（定位点/引线/气泡/翻转）。

### Task 2: 撤销 ✅
`History/History.swift`：文档快照栈，上限 100，新改动清空重做。

### Task 3: 编辑状态机 ✅
`Editor/EditorModel.swift`：工具切换、每个工具记忆颜色和粗细、拖拽绘制（⇧ 约束）、点击过小丢弃、画笔单击成点、无工具时选中/移动/删除、改样式作用于选中项、文本新建/编辑/清空即删除、标签点定位点翻转、双击任意工具下编辑文字、马赛克模式、水印设置。
测试：`EditorModelTests`（13 个）。

### Task 4: 渲染与导出 ✅
`Render/{AnnotationRenderer,Mosaic,Compositor}.swift`：绘制顺序 马赛克→高亮→形状→文字→水印；水印 −30° 交错平铺且只在选区内；马赛克用预先生成的整图像素化版本做蒙版。
测试：`RenderTests`（8 个，像素断言）。

### Task 5: App 集成 ✅
`App/Editor/{ToolbarControls,SubToolbar,WatermarkPanel,TextInputView,AnnotationCanvasView}.swift`，`App/Capture/{CaptureToolbar,OverlayView}.swift`
- 主工具栏按设计文档顺序；二级工具栏：粗细点 / 小中大字号 / 马赛克模式 + 颜色
- 文本输入框字体和位置与 CoreText 渲染一致；标签输入框带气泡底色
- 水印面板实时预览，关闭时记为一步撤销
- ⌘Z / ⇧⌘Z / Delete；画布 frame 限定为选区以减少内存

### 验收记录（2026-09-25）
- `swift test`：40 tests, 0 failures
- 离屏渲染核对：屏幕画布与导出 PNG 一致（矩形/椭圆/箭头/马赛克/高亮/文本/标签/水印）
- Release `.app` 916 KB，DMG 668 KB；空闲 11 MB，演示会话 41 MB
- 需人工验证：真实拖拽手感、文字输入法（中文 IME）、多屏
