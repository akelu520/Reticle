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
    struct Difference {
        /// Mean absolute difference, 0–255.
        var mean: Float
        /// Share of compared samples that differ by more than `outlierThreshold`: content that
        /// does not line up. Low-contrast changes (hover highlights, faint watermarks) stay below it.
        var outliers: Float
    }

    static let outlierThreshold: Float = 28

    static func difference(prev: RowFeatures, cur: RowFeatures, dy: Int, step: Int, minOverlap: Int) -> Difference? {
        let h = min(prev.height, cur.height)
        let y0 = max(0, -dy), y1 = min(h, h - dy)
        guard y1 - y0 >= minOverlap else { return nil }
        let b = blocks
        var total: Float = 0
        var outliers = 0
        var count = 0
        var y = y0
        while y < y1 {
            let p = (y + dy) * b, c = y * b
            for k in 0..<b {
                let d = abs(prev.values[p + k] - cur.values[c + k])
                total += d
                if d > outlierThreshold { outliers += 1 }
            }
            count += b
            y += step
        }
        return Difference(mean: total / Float(count), outliers: Float(outliers) / Float(count))
    }
}

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
    /// Shift of the last frame that moved: scrolling is continuous, so the next shift is close to it.
    private var lastShift = 0

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
            lastShift = 0
            return .started
        }
        guard frame.width == width, frame.height == frameHeight else { return .mismatch }
        if height >= maxHeight { return .limitReached }

        guard let dy = Self.estimateShift(prev: reference, cur: features, predicted: lastShift) else { return .mismatch }
        if dy == 0 {
            lastShift = 0
            return .unchanged
        }
        lastShift = dy

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
    /// Vertical shift of `cur` relative to `prev`, or nil when they do not match.
    ///
    /// Candidates are ranked by how much content fails to line up (`outliers`), which low-contrast
    /// changes such as hover highlights do not affect. Repetitive content (table rows, list items)
    /// can line up equally well at several shifts; the one closest to `predicted`, the previous
    /// frame's shift, wins such ties, since scrolling is continuous.
    static func estimateShift(prev: RowFeatures, cur: RowFeatures, predicted: Int = 0) -> Int? {
        let h = min(prev.height, cur.height)
        let maxShift = Int(Double(h) * 0.8)
        let minOverlap = max(h / 5, 4)
        guard let zero = RowFeatures.difference(prev: prev, cur: cur, dy: 0, step: 1, minOverlap: minOverlap) else { return nil }
        // Nothing lines up differently: not scrolled (at most a hover effect or animation).
        if zero.mean < 0.5 || zero.outliers < Self.stillOutliers { return 0 }

        var coarse: [(dy: Int, diff: RowFeatures.Difference)] = []
        var dy = -maxShift
        while dy <= maxShift {
            if let d = RowFeatures.difference(prev: prev, cur: cur, dy: dy, step: 4, minOverlap: minOverlap) { coarse.append((dy, d)) }
            dy += 4
        }
        // Local minima of the mean difference are the candidate shifts.
        var minima = coarse.indices.filter { i in
            (i == 0 || coarse[i].diff.mean <= coarse[i - 1].diff.mean)
                && (i == coarse.count - 1 || coarse[i].diff.mean <= coarse[i + 1].diff.mean)
        }
        // Refine only the promising ones; the coarse pass already separates the rest.
        if let coarseBest = minima.map({ coarse[$0].diff.outliers }).min() {
            minima = minima.filter { coarse[$0].diff.outliers <= coarseBest + 0.02 }
        }
        let refined = minima.compactMap { i -> (dy: Int, diff: RowFeatures.Difference)? in
            var best: (dy: Int, diff: RowFeatures.Difference)?
            for d in (coarse[i].dy - 4)...(coarse[i].dy + 4) where abs(d) <= maxShift {
                if let diff = RowFeatures.difference(prev: prev, cur: cur, dy: d, step: 1, minOverlap: minOverlap),
                   best == nil || diff.mean < best!.diff.mean {
                    best = (d, diff)
                }
            }
            return best
        }
        guard let fewest = refined.map(\.diff.outliers).min() else { return nil }
        let ties = refined.filter { $0.diff.outliers <= fewest + Self.tieOutliers }
        guard let chosen = ties.min(by: { abs($0.dy - predicted) < abs($1.dy - predicted) }) else { return nil }
        // Content lines up (a moving fixed overlay or hover may remain), or a close match overall.
        guard chosen.diff.outliers < Self.matchOutliers || chosen.diff.mean < 4 else { return nil }
        return chosen.dy
    }

    /// Outlier shares: below `stillOutliers` at zero shift means not scrolled; candidates within
    /// `tieOutliers` of the best are equally good; a match needs fewer than `matchOutliers`.
    static let stillOutliers: Float = 0.002
    static let tieOutliers: Float = 0.002
    static let matchOutliers: Float = 0.03

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
