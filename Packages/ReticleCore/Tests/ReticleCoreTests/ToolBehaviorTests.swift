import CoreGraphics
import XCTest
@testable import ReticleCore

/// Batch 2: text styles and point sizes, mosaic vs blur with strength, spotlight highlight, watermark.
final class ToolBehaviorTests: XCTestCase {
    func canvas(width: Int = 200, height: Int = 120, checker: Bool = false) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        if checker {
            ctx.setFillColor(CGColor(gray: 0, alpha: 1))
            for y in stride(from: 0, to: height, by: 2) {
                for x in stride(from: (y / 2) % 2 * 2, to: width, by: 4) { ctx.fill(CGRect(x: x, y: y, width: 2, height: 2)) }
            }
        }
        return ctx.makeImage()!
    }

    func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> [UInt8] { RenderTests().pixel(image, x, y) }

    func render(_ doc: Document, base: CGImage) -> CGImage {
        Compositor.render(base: base, effects: EffectSources(base: base, scale: 1), document: doc,
                          crop: CGRect(x: 0, y: 0, width: base.width, height: base.height))!
    }

    // MARK: Text

    func testTextDefaultsTo12ptAndSizeChangesApply() {
        var m = EditorModel(scale: 2)
        m.tool = .text
        _ = m.pointerDown(at: CGPoint(x: 5, y: 5))
        XCTAssertEqual(m.pendingTextStyle?.fontSize, 24, "12 pt × 2")
        m.finishText("A")
        m.tool = nil
        _ = m.pointerDown(at: CGPoint(x: 8, y: 8), clickCount: 1)
        m.pointerUp()
        m.setFontSize(20)
        XCTAssertEqual(m.document.annotations[0].style.fontSize, 40)
        XCTAssertEqual(m.currentPreset?.fontSize, 20)
        XCTAssertEqual(EditorModel.fontSizeChoices.first, 12)
    }

    func testTextBackgroundStyleFillsBehindText() {
        let base = canvas()
        var style = Style(color: .blue, lineWidth: 3, fontSize: 24)
        style.textStyle = .background
        let text = Annotation(kind: .text, points: [CGPoint(x: 20, y: 20)], style: style, text: "i")
        let out = render(Document(annotations: [text]), base: base)
        let b = text.bounds
        let corner = pixel(out, Int(b.maxX) - 3, Int(b.maxY) - 3)
        XCTAssertLessThan(corner[0], 120, "background box uses the text color (blue)")
        XCTAssertGreaterThan(corner[2], 180)
    }

    func testTextOutlineStyleAddsContrastingStroke() {
        var plain = Style(color: .red, lineWidth: 3, fontSize: 40)
        let outlined = { () -> Style in var s = plain; s.textStyle = .outline; return s }()
        plain.textStyle = .plain
        let a = Annotation(kind: .text, points: [CGPoint(x: 10, y: 10)], style: plain, text: "W")
        let b = Annotation(kind: .text, points: [CGPoint(x: 10, y: 10)], style: outlined, text: "W")
        XCTAssertGreaterThan(b.bounds.width, a.bounds.width - 0.01, "outline never shrinks the text")
        let base = canvas()
        XCTAssertNotEqual(ImageEncoder.png(render(Document(annotations: [a]), base: base)),
                          ImageEncoder.png(render(Document(annotations: [b]), base: base)))
    }

    // MARK: Mosaic

    func testMosaicStrengthChangesBlockSize() {
        let base = canvas(checker: true)
        let fx = EffectSources(base: base, scale: 1)
        var weak = Style(color: .red, lineWidth: 10, fontSize: 12); weak.strength = 0
        var strong = weak; strong.strength = 1
        XCTAssertEqual(EffectSources.blockSize(strength: 0.5, scale: 1), 8)
        XCTAssertLessThan(EffectSources.blockSize(strength: 0, scale: 1), EffectSources.blockSize(strength: 1, scale: 1))
        XCTAssertNotNil(fx.image(for: weak))
        XCTAssertTrue(fx.image(for: weak) !== fx.image(for: strong))
        XCTAssertTrue(fx.image(for: weak) === fx.image(for: weak), "cached")
    }

    func testBlurSmoothsCheckerToGray() {
        let base = canvas(checker: true)
        var style = Style(color: .red, lineWidth: 10, fontSize: 12)
        style.effect = .blur
        style.strength = 0.5
        let box = Annotation(kind: .mosaicBox, points: [CGPoint(x: 20, y: 20), CGPoint(x: 180, y: 100)], style: style)
        let out = render(Document(annotations: [box]), base: base)
        for (x, y) in [(60, 60), (61, 60), (60, 61)] {
            let v = Int(pixel(out, x, y)[0])
            XCTAssertTrue((60...200).contains(v), "blurred checker is mid gray, got \(v)")
        }
    }

    func testMosaicToolRecordsEffectAndStrength() {
        var m = EditorModel(scale: 1)
        m.tool = .mosaic
        m.setMosaicEffect(.blur)
        m.setStrength(0.8)
        m.mosaicMode = .box
        _ = m.pointerDown(at: .zero); m.pointerDragged(to: CGPoint(x: 40, y: 40)); m.pointerUp()
        XCTAssertEqual(m.document.annotations[0].style.effect, .blur)
        XCTAssertEqual(m.document.annotations[0].style.strength, 0.8, accuracy: 0.001)
    }

    // MARK: Highlight (spotlight)

    func testHighlightDimsEverythingOutsideTheShape() {
        let base = canvas()
        var style = Style(color: .red, lineWidth: 3, fontSize: 12)
        style.opacity = 0.5
        style.shape = .rect
        let h = Annotation(kind: .highlight, points: [CGPoint(x: 50, y: 30), CGPoint(x: 150, y: 90)], style: style)
        let out = render(Document(annotations: [h]), base: base)
        XCTAssertEqual(pixel(out, 100, 60), [255, 255, 255, 255], "inside stays bright")
        let outside = Int(pixel(out, 10, 10)[0])
        XCTAssertTrue((110...145).contains(outside), "outside dimmed by 50%, got \(outside)")
    }

    func testHighlightToolIsShapeBased() {
        var m = EditorModel(scale: 1)
        m.tool = .highlight
        m.setHighlightShape(.ellipse)
        m.setOpacity(0.3)
        _ = m.pointerDown(at: CGPoint(x: 10, y: 10)); m.pointerDragged(to: CGPoint(x: 5, y: 5)); m.pointerDragged(to: CGPoint(x: 90, y: 60)); m.pointerUp()
        let a = m.document.annotations[0]
        XCTAssertEqual(a.kind, .highlight)
        XCTAssertEqual(a.points.count, 2, "a shape, not a stroke")
        XCTAssertEqual(a.style.shape, .ellipse)
        XCTAssertEqual(a.style.opacity, 0.3, accuracy: 0.001)
        XCTAssertTrue(a.hitTest(CGPoint(x: 50, y: 35), tolerance: 0))
    }

    // MARK: Watermark

    func testWatermarkTextIsLimitedTo16Characters() {
        XCTAssertEqual(Watermark.limited("一二三四五六七八九十一二三四五六七八"), "一二三四五六七八九十一二三四五六")
        XCTAssertEqual(Watermark.defaultOpacity, 0.3)
    }
}
