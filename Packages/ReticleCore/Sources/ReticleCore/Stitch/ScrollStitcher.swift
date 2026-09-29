import CoreGraphics
import Foundation

/// Per-row fingerprint of a frame: each row reduced to `blocks` column-block
/// gray averages. Vertical detail is kept at full resolution, which is what
/// matters for finding a vertical scroll offset.
struct RowFeatures {
    static let blocks = 64

    let width: Int
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
        for y in 0..<h {
            let row = data + y * bytesPerRow
            for k in 0..<b {
                let x0 = k * w / b, x1 = (k + 1) * w / b
                var sum = 0
                for x in x0..<x1 { sum += Int(row[x]) }
                values[y * b + k] = Float(sum) / Float(x1 - x0)
            }
        }
        self.width = w
        self.height = h
        self.values = values
    }

    struct Difference {
        /// Mean absolute difference, 0–255.
        var mean: Float
        /// Share of compared samples that differ by more than `outlierThreshold`: content that
        /// does not line up. Low-contrast changes (hover highlights, faint watermarks) stay below it.
        var outliers: Float
    }

    static let outlierThreshold: Float = 28
    /// Samples closer than this between two frames at the same place did not change.
    static let stillThreshold: Float = 6

    /// Samples that did not change between `prev` and `cur` at the same place: sticky bars,
    /// floating buttons and plain background. They say nothing about the scroll shift.
    static func stillMask(prev: RowFeatures, cur: RowFeatures) -> [Bool] {
        let n = min(prev.values.count, cur.values.count)
        return (0..<n).map { abs(prev.values[$0] - cur.values[$0]) < stillThreshold }
    }

    /// Compares `prev` shifted by `dy` with `cur`, skipping samples in `mask` in either frame.
    static func difference(prev: RowFeatures, cur: RowFeatures, dy: Int, step: Int, minOverlap: Int, ignoring mask: [Bool]? = nil) -> Difference? {
        let h = min(prev.height, cur.height)
        let y0 = max(0, -dy), y1 = min(h, h - dy)
        guard y1 - y0 >= minOverlap else { return nil }
        let b = blocks
        var total: Float = 0
        var outliers = 0
        var count = 0
        var y = y0
        prev.values.withUnsafeBufferPointer { pv in
            cur.values.withUnsafeBufferPointer { cv in
                while y < y1 {
                    let p = (y + dy) * b, c = y * b
                    if let mask {
                        for k in 0..<b where !mask[c + k] && !mask[p + k] {
                            let d = abs(pv[p + k] - cv[c + k])
                            total += d
                            if d > outlierThreshold { outliers += 1 }
                            count += 1
                        }
                    } else {
                        for k in 0..<b {
                            let d = abs(pv[p + k] - cv[c + k])
                            total += d
                            if d > outlierThreshold { outliers += 1 }
                        }
                        count += b
                    }
                    y += step
                }
            }
        }
        // Too little moving content in the overlap to judge.
        guard count >= max(b, (y1 - y0) / step * b / 50) else { return nil }
        return Difference(mean: total / Float(count), outliers: Float(outliers) / Float(count))
    }

    /// Regions fixed to the viewport while the content scrolled by `dy`: unchanged in place,
    /// but different from the content that scrolled there. In pixels, top-down.
    static func fixedRegions(prev: RowFeatures, cur: RowFeatures, dy: Int, still: [Bool]) -> [CGRect] {
        let h = min(prev.height, cur.height), b = blocks, bin = 8
        let bins = h / bin
        guard bins > 0 else { return [] }
        var grid = [Bool](repeating: false, count: bins * b)
        for r in 0..<bins {
            for k in 0..<b {
                var hits = 0
                for y in (r * bin)..<(r * bin + bin) where y + dy >= 0 && y + dy < h {
                    let c = y * b + k, v = cur.values[c]
                    // Stayed put, differs from the content that scrolled into place, and differs from
                    // the page one shift away. The last rules out plain background that only looks
                    // fixed because a fixed region slid over it ("ghosts" one shift away); at the
                    // frame edge (sticky bars) there is nothing to compare with.
                    let away = y - dy >= 0 && y - dy < h ? cur.values[(y - dy) * b + k] : nil
                    if still[c], abs(v - prev.values[(y + dy) * b + k]) > outlierThreshold,
                       away.map({ abs(v - $0) > outlierThreshold }) ?? true {
                        hits += 1
                    }
                }
                grid[r * b + k] = hits * 4 >= bin
            }
        }
        // Connected groups of bins; isolated specks are noise.
        var seen = [Bool](repeating: false, count: grid.count)
        var rects: [CGRect] = []
        for start in grid.indices where grid[start] && !seen[start] {
            var stack = [start], cells: [Int] = []
            seen[start] = true
            while let i = stack.popLast() {
                cells.append(i)
                let r = i / b, k = i % b
                for (nr, nk) in [(r - 1, k), (r + 1, k), (r, k - 1), (r, k + 1)] where nr >= 0 && nr < bins && nk >= 0 && nk < b {
                    let j = nr * b + nk
                    if grid[j], !seen[j] { seen[j] = true; stack.append(j) }
                }
            }
            guard cells.count >= 3 else { continue }
            let rows = cells.map { $0 / b }, cols = cells.map { $0 % b }
            // One bin / block of margin for anti-aliased edges and shadows.
            let r0 = max(rows.min()! - 1, 0), r1 = min(rows.max()! + 2, bins)
            let k0 = max(cols.min()! - 1, 0), k1 = min(cols.max()! + 2, b)
            let x0 = k0 * cur.width / b, x1 = k1 * cur.width / b
            let y1 = r1 == bins ? h : r1 * bin
            rects.append(CGRect(x: x0, y: r0 * bin, width: x1 - x0, height: y1 - r0 * bin))
        }
        return rects
    }
}

public final class ScrollStitcher {
    public enum Update: Equatable, Sendable {
        case started
        case moved(Int)
        case unchanged
        case mismatch
        case limitReached
    }

    public let maxHeight: Int
    private var width = 0
    private var frameHeight = 0
    private var reference: RowFeatures?
    private var position = 0
    private var top = 0
    private var bottom = 0
    private var strips: [(y: Int, image: CGImage)] = []
    /// Shift of the last frame that moved: scrolling is continuous, so the next shift is close to it.
    private var lastShift = 0
    /// Viewport regions (pixels, top-down) that stay put while the page scrolls: floating buttons,
    /// sticky bars.
    private var fixed: [CGRect] = []
    /// Areas of the long image (y in stitch coordinates) that show a fixed region instead of the
    /// page; replaced once a later frame shows the page there.
    private var covered: [CGRect] = []
    private var patches: [(rect: CGRect, image: CGImage)] = []

    public init(maxHeight: Int = 30000) {
        self.maxHeight = maxHeight
    }

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

        let still = RowFeatures.stillMask(prev: reference, cur: features)
        var shift = Self.estimateShift(prev: reference, cur: features, predicted: lastShift, ignoring: fixedMask)
        if shift == nil {
            // Something fixed to the viewport, e.g. a sticky bar, may spoil the match. Leave out
            // everything that stayed put to find it, then match again without just that.
            if let guess = Self.estimateShift(prev: reference, cur: features, predicted: lastShift, ignoring: still), guess != 0 {
                let found = RowFeatures.fixedRegions(prev: reference, cur: features, dy: guess, still: still)
                if addFixed(found), let again = Self.estimateShift(prev: reference, cur: features, predicted: lastShift, ignoring: fixedMask),
                   abs(again - guess) <= 4 {
                    shift = again
                }
            }
        }
        guard let dy = shift else { return .mismatch }
        if dy == 0 {
            lastShift = 0
            return .unchanged
        }
        lastShift = dy
        addFixed(RowFeatures.fixedRegions(prev: reference, cur: features, dy: dy, still: still))

        let newPos = position + dy
        uncover(with: frame, at: newPos)
        if newPos + frameHeight > bottom {
            let rows = (bottom - newPos)..<frameHeight
            if let strip = Self.copy(frame, rows: rows) { strips.append((bottom, strip)) }
            markCovered(rows: rows, at: newPos)
            bottom = newPos + frameHeight
        }
        if newPos < top {
            let rows = 0..<(top - newPos)
            if let strip = Self.copy(frame, rows: rows) { strips.append((newPos, strip)) }
            markCovered(rows: rows, at: newPos)
            top = newPos
        }
        position = newPos
        self.reference = features
        return .moved(dy)
    }

    /// Samples inside `fixed`, left out when matching.
    private var fixedMask: [Bool]?

    /// Records newly found fixed regions; they also covered the previous frame's place in the image.
    @discardableResult
    private func addFixed(_ regions: [CGRect]) -> Bool {
        let new = regions.filter { r in !fixed.contains { $0.contains(r) } }
        guard !new.isEmpty else { return false }
        for r in new {
            fixed.append(r)
            covered.append(r.offsetBy(dx: 0, dy: CGFloat(position)))
        }
        let b = RowFeatures.blocks
        var mask = [Bool](repeating: false, count: frameHeight * b)
        for r in fixed {
            let k0 = Int(r.minX) * b / width, k1 = min(b, (Int(r.maxX) * b + width - 1) / width)
            for y in max(0, Int(r.minY))..<min(frameHeight, Int(r.maxY)) {
                for k in k0..<k1 { mask[y * b + k] = true }
            }
        }
        fixedMask = mask
        return true
    }

    /// Rows of a frame at `pos` just added to the image: where they show a fixed region, the page is hidden.
    private func markCovered(rows: Range<Int>, at pos: Int) {
        let band = CGRect(x: 0, y: rows.lowerBound, width: width, height: rows.count)
        for r in fixed {
            let part = r.intersection(band)
            if !part.isEmpty { covered.append(part.offsetBy(dx: 0, dy: CGFloat(pos))) }
        }
    }

    /// Replaces covered areas that this frame, at `pos`, shows free of fixed regions.
    private func uncover(with frame: CGImage, at pos: Int) {
        covered.removeAll { area in
            let inFrame = area.offsetBy(dx: 0, dy: CGFloat(-pos))
            guard inFrame.minY >= 0, inFrame.maxY <= CGFloat(frameHeight),
                  !fixed.contains(where: { $0.intersects(inFrame) }),
                  let crop = frame.cropping(to: inFrame), let image = Self.copy(crop, rows: 0..<crop.height) else { return false }
            patches.append((area, image))
            return true
        }
    }

    /// Vertical shift of `cur` relative to `prev` (`prev[y + dy] ≈ cur[y]`), or nil when they do not match.
    ///
    /// Samples in `mask` (regions fixed to the viewport) are left out. Candidates are ranked by how much content fails to line up (`outliers`), which
    /// low-contrast changes such as hover highlights do not affect. Repetitive content (table
    /// rows, list items) can line up equally well at several shifts; the one closest to
    /// `predicted`, the previous frame's shift, wins such ties, since scrolling is continuous.
    static func estimateShift(prev: RowFeatures, cur: RowFeatures, predicted: Int = 0, ignoring mask: [Bool]? = nil) -> Int? {
        let h = min(prev.height, cur.height)
        let maxShift = Int(Double(h) * 0.8)
        let minOverlap = max(h / 5, 4)
        guard let zero = RowFeatures.difference(prev: prev, cur: cur, dy: 0, step: 1, minOverlap: minOverlap) else { return nil }
        // Nothing lines up differently: not scrolled (at most a hover effect or animation).
        if zero.mean < 0.5 || zero.outliers < Self.stillOutliers { return 0 }

        var coarse: [(dy: Int, diff: RowFeatures.Difference)] = []
        var dy = -maxShift
        while dy <= maxShift {
            if let d = RowFeatures.difference(prev: prev, cur: cur, dy: dy, step: 4, minOverlap: minOverlap, ignoring: mask) {
                coarse.append((dy, d))
            }
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
                if let diff = RowFeatures.difference(prev: prev, cur: cur, dy: d, step: 1, minOverlap: minOverlap, ignoring: mask),
                   best == nil || diff.mean < best!.diff.mean {
                    best = (d, diff)
                }
            }
            return best
        }
        guard let fewest = refined.map(\.diff.outliers).min() else { return nil }
        let ties = refined.filter { $0.diff.outliers <= fewest + Self.tieOutliers }
        guard let chosen = ties.min(by: { abs($0.dy - predicted) < abs($1.dy - predicted) }) else { return nil }
        // Content lines up (a hover effect may remain), or a close match overall.
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
            ctx.draw(strip.image, in: CGRect(x: 0, y: CGFloat(h) - y - sh, width: CGFloat(w), height: sh))
        }
        // The page where fixed regions covered it.
        for patch in patches {
            let r = patch.rect
            let y = (r.minY - CGFloat(top)) * scale
            ctx.draw(patch.image, in: CGRect(x: r.minX * scale, y: CGFloat(h) - y - r.height * scale,
                                             width: r.width * scale, height: r.height * scale))
        }
        return ctx.makeImage()
    }

    static func copy(_ frame: CGImage, rows: Range<Int>) -> CGImage? {
        guard !rows.isEmpty, let cropped = frame.cropping(to: CGRect(x: 0, y: rows.lowerBound, width: frame.width, height: rows.count)),
              let ctx = CGContext(data: nil, width: cropped.width, height: cropped.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: frame.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: cropped.width, height: cropped.height))
        return ctx.makeImage()
    }
}
