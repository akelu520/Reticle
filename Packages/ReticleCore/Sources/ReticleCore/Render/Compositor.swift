import CoreGraphics

/// Produces the final exported image from a captured screen image.
public enum Compositor {
    /// Crops `image` to `pixelRect` (top-left origin), clamped to the image bounds.
    public static func crop(_ image: CGImage, to pixelRect: CGRect) -> CGImage? {
        let r = clampedRect(pixelRect, in: image)
        guard let r else { return nil }
        return image.cropping(to: r)
    }

    /// Base image cropped to `pixelRect` with annotations and watermark burned in.
    public static func render(base: CGImage, pixelated: CGImage?, document: Document, crop pixelRect: CGRect) -> CGImage? {
        if document.annotations.isEmpty && document.watermark == nil { return crop(base, to: pixelRect) }
        guard let r = clampedRect(pixelRect, in: base),
              let ctx = CGContext(data: nil, width: Int(r.width), height: Int(r.height), bitsPerComponent: 8, bytesPerRow: 0,
                                  space: base.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // Switch to a y-down space in full-image pixel coordinates.
        ctx.translateBy(x: 0, y: r.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.translateBy(x: -r.minX, y: -r.minY)
        let baseSize = CGSize(width: base.width, height: base.height)
        AnnotationRenderer.drawImage(base, in: CGRect(origin: .zero, size: baseSize), ctx: ctx)
        AnnotationRenderer.draw(document.annotations, pixelated: pixelated, baseSize: baseSize, in: ctx)
        if let w = document.watermark {
            AnnotationRenderer.drawWatermark(w, in: r, ctx: ctx)
        }
        return ctx.makeImage()
    }

    private static func clampedRect(_ pixelRect: CGRect, in image: CGImage) -> CGRect? {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let r = pixelRect.integral.intersection(bounds)
        guard !r.isNull, r.width >= 1, r.height >= 1 else { return nil }
        return r
    }
}
