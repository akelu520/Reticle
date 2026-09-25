import CoreGraphics
import Foundation

/// Per-row fingerprint of a frame: each row reduced to `blocks` column-block
/// gray averages. Vertical detail is kept at full resolution, which is what
/// matters for finding a vertical scroll offset.
struct RowFeatures {
    static let blocks = 64

    let height: Int
    let values: [Float] // height × blocks

    init?(_ image: CGImage) {
        let w = image.width, h = image.height
        guard w >= Self.blocks, h >= 8,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.interpolationQuality = .none
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        let bytesPerRow = ctx.bytesPerRow
        let b = Self.blocks
        var values = [Float](repeating: 0, count: h * b)
        // CGBitmapContext memory starts at the top row.
        for y in 0..<h {
            let row = data + y * bytesPerRow
            for k in 0..<b {
                let x0 = k * w / b, x1 = (k + 1) * w / b
                var sum = 0
                for x in x0..<x1 { sum += Int(row[x]) }
                values[y * b + k] = Float(sum) / Float(x1 - x0)
            }
        }
        self.height = h
        self.values = values
    }

    /// Mean absolute difference between `prev` rows shifted by `dy` and these rows,
    /// over the overlap, sampling every `step` rows. `nil` when the overlap is too small.
    static func difference(prev: RowFeatures, cur: RowFeatures, dy: Int, step: Int, minOverlap: Int) -> Float? {
        let h = min(prev.height, cur.height)
        let y0 = max(0, -dy), y1 = min(h, h - dy)
        guard y1 - y0 >= minOverlap else { return nil }
        let b = blocks
        var total: Float = 0
        var count = 0
        var y = y0
        while y < y1 {
            let p = (y + dy) * b, c = y * b
            for k in 0..<b { total += abs(prev.values[p + k] - cur.values[c + k]) }
            count += b
            y += step
        }
        return total / Float(count)
    }
}

/// Stitches successive frames of a scrolling region into one tall image.
/// Supports scrolling both down and up. Not thread-safe; call from one queue.
public final class ScrollStitcher {
    public enum Update: Equatable, Sendable {
        case started
        /// Content moved by this many pixels (positive = scrolled down).
        case moved(Int)
        case unchanged
        /// No confident match (scrolling too fast, animation, etc.). The frame is ignored.
        case mismatch
        case limitReached
    }

    public let maxHeight: Int
    private var width = 0
    private var frameHeight = 0
    private var reference: RowFeatures?
    /// Content-space position of the reference frame's top row.
    private var position = 0
    private var top = 0
    private var bottom = 0
    private var strips: [(y: Int, image: CGImage)] = []

    public init(maxHeight: Int = 30000) {
        self.maxHeight = maxHeight
    }

    /// Current stitched height in pixels.
    public var height: Int { bottom - top }

    public func add(_ frame: CGImage) -> Update {
        guard let features = RowFeatures(frame) else { return .mismatch }
        guard let reference else {
            width = frame.width
            frameHeight = frame.height
            strips = Self.copy(frame, rows: 0..<frame.height).map { [(0, $0)] } ?? []
            self.reference = features
            position = 0
            top = 0
            bottom = frame.height
            return .started
        }
        guard frame.width == width, frame.height == frameHeight else { return .mismatch }
        if height >= maxHeight { return .limitReached }

        guard let dy = Self.estimateShift(prev: reference, cur: features) else { return .mismatch }
        if dy == 0 { return .unchanged }

        let newPos = position + dy
        if newPos + frameHeight > bottom {
            let rows = (bottom - newPos)..<frameHeight
            if let strip = Self.copy(frame, rows: rows) { strips.append((bottom, strip)) }
            bottom = newPos + frameHeight
        }
        if newPos < top {
            let rows = 0..<(top - newPos)
            if let strip = Self.copy(frame, rows: rows) { strips.append((newPos, strip)) }
            top = newPos
        }
        position = newPos
        self.reference = features
        return .moved(dy)
    }

    /// Vertical offset such that `prev[y + dy] ≈ cur[y]`, or nil when no confident match.
    static func estimateShift(prev: RowFeatures, cur: RowFeatures) -> Int? {
        let h = min(prev.height, cur.height)
        let maxShift = Int(Double(h) * 0.8)
        let minOverlap = max(h / 5, 4)
        guard let zero = RowFeatures.difference(prev: prev, cur: cur, dy: 0, step: 1, minOverlap: minOverlap) else { return nil }
        if zero < 0.5 { return 0 }

        // Coarse search every 4 rows (sampling every 4th row), then refine ±4 at full resolution.
        var best = (dy: 0, score: Float.greatestFiniteMagnitude)
        var dy = -maxShift
        while dy <= maxShift {
            if let s = RowFeatures.difference(prev: prev, cur: cur, dy: dy, step: 4, minOverlap: minOverlap), s < best.score {
                best = (dy, s)
            }
            dy += 4
        }
        var refined = (dy: 0, score: Float.greatestFiniteMagnitude)
        for d in (best.dy - 4)...(best.dy + 4) where abs(d) <= maxShift {
            if let s = RowFeatures.difference(prev: prev, cur: cur, dy: d, step: 1, minOverlap: minOverlap), s < refined.score {
                refined = (d, s)
            }
        }
        // Accept near-exact matches, or clear winners when part of the region is static.
        guard refined.score < 4 || refined.score < zero * 0.25 else { return nil }
        return refined.dy
    }

    /// The stitched image, optionally scaled down (for previews).
    public func compose(scale: CGFloat = 1) -> CGImage? {
        guard height > 0, width > 0 else { return nil }
        let w = max(Int(CGFloat(width) * scale), 1), h = max(Int(CGFloat(height) * scale), 1)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: strips.first?.image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = scale == 1 ? .none : .medium
        for strip in strips {
            let y = CGFloat(strip.y - top) * scale
            let sh = CGFloat(strip.image.height) * scale
            // CG context is y-up: convert the strip's top-down position.
            ctx.draw(strip.image, in: CGRect(x: 0, y: CGFloat(h) - y - sh, width: CGFloat(w), height: sh))
        }
        return ctx.makeImage()
    }

    /// Copies rows of `frame` into standalone memory, so capture buffers can be recycled.
    static func copy(_ frame: CGImage, rows: Range<Int>) -> CGImage? {
        guard !rows.isEmpty, let cropped = frame.cropping(to: CGRect(x: 0, y: rows.lowerBound, width: frame.width, height: rows.count)),
              let ctx = CGContext(data: nil, width: cropped.width, height: cropped.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: frame.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: cropped.width, height: cropped.height))
        return ctx.makeImage()
    }
}
