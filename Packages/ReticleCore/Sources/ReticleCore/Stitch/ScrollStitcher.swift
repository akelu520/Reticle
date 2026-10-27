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
    /// With `band`, only rows inside it in both frames are compared (the page's content rows,
    /// between fixed bars), and the overlap must be that large within the band.
    static func difference(prev: RowFeatures, cur: RowFeatures, dy: Int, step: Int, minOverlap: Int, ignoring mask: [Bool]? = nil,
                           band: Range<Int>? = nil) -> Difference? {
        let h = min(prev.height, cur.height)
        let rows = band ?? 0..<h
        let y0 = max(0, -dy, rows.lowerBound, rows.lowerBound - dy), y1 = min(h, h - dy, rows.upperBound, rows.upperBound - dy)
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

    /// Samples of row `ya` in `a` and row `yb` in `b` that clearly differ.
    static func differingSamples(_ a: RowFeatures, _ ya: Int, _ b: RowFeatures, _ yb: Int) -> Int {
        let n = blocks
        var count = 0
        for k in 0..<n where abs(a.values[ya * n + k] - b.values[yb * n + k]) > outlierThreshold { count += 1 }
        return count
    }

    /// Whether some row in `rows` clearly differs from row `other` of the same frame.
    static func contrasts(_ f: RowFeatures, rows: Range<Int>, with other: Int) -> Bool {
        guard other >= 0, other < f.height else { return false }
        return rows.contains { differingSamples(f, $0, f, other) >= 2 }
    }

    /// How many rows at the top and at the bottom are exactly the same in both frames.
    static func unchangedEdges(prev: RowFeatures, cur: RowFeatures) -> (top: Int, bottom: Int) {
        let h = min(prev.height, cur.height), n = blocks
        func unchanged(_ y: Int) -> Bool { (0..<n).allSatisfy { abs(cur.values[y * n + $0] - prev.values[y * n + $0]) < stillThreshold } }
        let top = (0..<h).first { !unchanged($0) } ?? h
        let bottom = (0..<h).first { !unchanged(h - 1 - $0) } ?? h
        return (top, bottom)
    }

    /// Whether row `y` shows something fixed to the viewport (an input box, a fade, a title bar)
    /// rather than page content scrolling by `dy`. Checked both ways: what `cur` shows there
    /// differs from the content that scrolled in, and what `prev` showed there differs from where
    /// that content went. A "ghost" — page content next to a fixed button, compared against the
    /// button — passes only the first check; plain background passes neither.
    ///
    /// Next to the frame edge there is nothing one shift away; there an unchanged row that differs
    /// from the content that scrolled in counts (an opaque bar).
    static func rowIsFixed(_ y: Int, prev: RowFeatures, cur: RowFeatures, dy: Int) -> Bool {
        let h = min(prev.height, cur.height), n = blocks
        guard y + dy >= 0, y + dy < h, differingSamples(cur, y, prev, y + dy) >= 2 else { return false }
        if y - dy >= 0, y - dy < h { return differingSamples(prev, y, cur, y - dy) >= 2 }
        return (0..<n).allSatisfy { abs(cur.values[y * n + $0] - prev.values[y * n + $0]) < stillThreshold }
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
    /// Pieces of the long image in the order they were taken: strips of new rows (full width)
    /// and patches; later pieces cover earlier ones. `y` in stitch coordinates.
    private var pieces: [(x: Int, y: Int, image: CGImage)] = []
    /// Where the long image ends, including the last frame's fixed footer (`bottom` is where the
    /// page content proven so far ends; anything below it is replaced by the next strip).
    private var end = 0
    /// Where the long image starts, including the first frame's fixed header (`top` is where the
    /// page content proven so far starts; anything above it is replaced by the next strip up).
    private var start = 0
    /// Rows from here down to the bottom of the viewport stay put (an input box, a fade): the page
    /// content of a frame ends here. Learned from frames that could show it.
    private var footerTop: Int?
    /// Rows above this stay put (a title bar, a fade): the page content of a frame starts here.
    private var headerBottom: Int?
    /// Positions of the frames whose rows were taken below / above earlier edges: when an edge is
    /// found to reach further, those rows near it showed the fade, and are patched later.
    private var appendedAt: [Int] = []
    private var prependedAt: [Int] = []
    /// Rows at the bottom / top edge that stayed identical over a run of scrolling, and how far the
    /// page moved meanwhile.
    private var stillBottom = (rows: 0, moved: 0)
    private var stillTop = (rows: 0, moved: 0)
    /// Shift of the last frame that moved: scrolling is continuous, so the next shift is close to it.
    private var lastShift = 0
    /// Viewport regions (pixels, top-down) that stay put while the page scrolls: floating buttons,
    /// sticky bars.
    private var fixed: [CGRect] = []
    /// Areas of the long image (y in stitch coordinates) that show a fixed region instead of the
    /// page; replaced once a later frame shows the page there.
    private var covered: [CGRect] = []

    public init(maxHeight: Int = 30000) {
        self.maxHeight = maxHeight
    }

    public var height: Int { end - start }

    public func add(_ frame: CGImage) -> Update {
        guard let features = RowFeatures(frame) else { return .mismatch }
        guard let reference else {
            width = frame.width
            frameHeight = frame.height
            pieces = Self.copy(frame, rows: 0..<frame.height).map { [(0, 0, $0)] } ?? []
            self.reference = features
            position = 0
            top = 0
            bottom = frame.height
            end = frame.height
            start = 0
            footerTop = nil
            headerBottom = nil
            appendedAt = [0]
            prependedAt = [0]
            stillBottom = (0, 0)
            stillTop = (0, 0)
            lastShift = 0
            return .started
        }
        guard frame.width == width, frame.height == frameHeight else { return .mismatch }
        if height >= maxHeight { return .limitReached }

        let still = RowFeatures.stillMask(prev: reference, cur: features)
        // The whole frame, and — once fixed bars are known — only the page's content rows between
        // them. Fixed bars and fades can keep the first from matching, or pull it to a look-alike
        // shift of repetitive content; a big jump can leave too little overlap for the second.
        var shift = Self.estimateShift(prev: reference, cur: features, predicted: lastShift)
        let band = (headerBottom ?? 0)..<(footerTop ?? frameHeight)
        if band.count >= frameHeight / 3, band.count < frameHeight,
           let inBand = Self.estimateShift(prev: reference, cur: features, predicted: lastShift, ignoring: fixedMask, band: band), inBand != shift {
            shift = shift.map { whole in
                Self.better(whole, inBand, prev: reference, cur: features, ignoring: fixedMask, predicted: lastShift)
            } ?? inBand
        }
        if shift == nil, headerBottom == nil || footerTop == nil {
            // Bars not learned yet: rows at the edges that did not change at all are one (an opaque
            // sticky bar or input box).
            let edges = RowFeatures.unchangedEdges(prev: reference, cur: features)
            let still = edges.top..<(frameHeight - edges.bottom)
            if still.count >= frameHeight / 3, still.count < frameHeight {
                shift = Self.estimateShift(prev: reference, cur: features, predicted: lastShift, ignoring: fixedMask, band: still)
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
        learnStillEdges(prev: reference, cur: features, dy: dy)
        let contentEnd = pageContentEnd(prev: reference, cur: features, dy: dy)
        let contentStart = min(pageContentStart(prev: reference, cur: features, dy: dy), contentEnd)
        // What the frame that last extended the image showed beyond these edges was a footer or
        // header, not the page: the next strip replaces it.
        bottom = min(bottom, end - frameHeight + contentEnd)
        top = max(top, start + contentStart)
        uncover(with: frame, at: newPos, rows: contentStart..<contentEnd)
        if newPos + contentEnd > bottom {
            // New page rows, plus this frame's footer as a provisional end of the image.
            let first = max(0, bottom - newPos)
            if let strip = Self.copy(frame, rows: first..<frameHeight) { pieces.append((0, newPos + first, strip)) }
            markCovered(rows: first..<contentEnd, at: newPos)
            appendedAt.append(newPos)
            bottom = newPos + contentEnd
            end = newPos + frameHeight
        }
        if newPos + contentStart < top {
            // New page rows above, plus this frame's header as a provisional start of the image.
            let last = min(frameHeight, top - newPos)
            if let strip = Self.copy(frame, rows: 0..<last) { pieces.append((0, newPos, strip)) }
            markCovered(rows: contentStart..<last, at: newPos)
            prependedAt.append(newPos)
            top = newPos + contentStart
            start = newPos
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
        // It covered the page in every frame taken so far, not just the last one.
        let earlier = Set(appendedAt + prependedAt + [position])
        for r in new {
            fixed.append(r)
            for p in earlier { covered.append(r.offsetBy(dx: 0, dy: CGFloat(p))) }
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

    /// Where the page content of `cur` ends: above the highest row in the lower half that did not
    /// scroll with the page. Fades show this only where text passes through them, so the edge
    /// only ever moves up, and rows the shift scrolled in from below (which cannot be checked)
    /// stay behind a footer seen before.
    private func pageContentEnd(prev: RowFeatures, cur: RowFeatures, dy: Int) -> Int {
        let h = frameHeight
        let checkable = dy >= 0 ? (h / 2)..<max(h / 2, h - dy) : max(h / 2, -dy)..<h
        if let y = checkable.first(where: { RowFeatures.rowIsFixed($0, prev: prev, cur: cur, dy: dy) }),
           y - (headerBottom ?? 0) >= h / 3 {
            // Plus a margin: the faint end of a fade dims text too little to detect, yet visibly.
            moveFooterEdge(to: y - Self.edgeMargin(h))
        }
        return footerTop ?? h
    }

    static func edgeMargin(_ h: Int) -> Int { max(4, h / 20) }

    /// The page content of a frame ends at `y` or above: the footer edge only moves up (never past
    /// the middle), and rows taken below it before are patched.
    private func moveFooterEdge(to y: Int) {
        let h = frameHeight
        let edge = min(footerTop ?? h, max(y, h / 2))
        markFade(rows: edge..<(footerTop ?? h), at: appendedAt)
        footerTop = edge
    }

    /// The page content of a frame starts at `y` or below; the header edge only moves down.
    private func moveHeaderEdge(to y: Int) {
        let h = frameHeight
        let edge = max(headerBottom ?? 0, min(y, h / 2))
        markFade(rows: (headerBottom ?? 0)..<edge, at: prependedAt)
        headerBottom = edge
    }

    /// A thin line fixed along an edge (a window border, a 1–3 px fixed bar) lies entirely in the
    /// rows that scrolled in this frame, so it cannot be checked against the page. Instead: rows at
    /// the edge that stay identical while the page moves at least a quarter of the frame past them,
    /// and that contrast with the page next to them (plain background only looks the same).
    private func learnStillEdges(prev: RowFeatures, cur: RowFeatures, dy: Int) {
        let h = frameHeight
        let edges = RowFeatures.unchangedEdges(prev: prev, cur: cur)
        func extend(_ run: inout (rows: Int, moved: Int), _ k: Int) -> Int? {
            if k == 0 {
                run = (0, 0)
                return nil
            }
            // A tall unchanged band is plain background passing by: keep the run, learn nothing.
            guard k < h / 4 else { return nil }
            run = run.rows == 0 ? (k, abs(dy)) : (min(run.rows, k), run.moved + abs(dy))
            return run.moved >= h / 4 ? run.rows : nil
        }
        if let k = extend(&stillBottom, edges.bottom), RowFeatures.contrasts(cur, rows: (h - k)..<h, with: h - k - 1) {
            moveFooterEdge(to: h - k - 2)
        }
        if let k = extend(&stillTop, edges.top), RowFeatures.contrasts(cur, rows: 0..<k, with: k) {
            moveHeaderEdge(to: k + 2)
        }
    }

    /// Rows of earlier frames (at `positions`) that turned out to be part of a fixed bar or fade.
    private func markFade(rows: Range<Int>, at positions: [Int]) {
        guard !rows.isEmpty else { return }
        for p in positions { covered.append(CGRect(x: 0, y: p + rows.lowerBound, width: width, height: rows.count)) }
    }

    /// Where the page content of `cur` starts: below the lowest row in the upper half that did
    /// not scroll with the page; like the footer edge, it only ever moves down.
    private func pageContentStart(prev: RowFeatures, cur: RowFeatures, dy: Int) -> Int {
        let h = frameHeight
        let checkable = dy >= 0 ? 0..<min(h / 2, h - dy) : min(h / 2, -dy)..<(h / 2)
        if let y = checkable.reversed().first(where: { RowFeatures.rowIsFixed($0, prev: prev, cur: cur, dy: dy) }),
           (footerTop ?? h) - (y + 1) >= h / 3 {
            moveHeaderEdge(to: y + 1 + Self.edgeMargin(h))
        }
        return headerBottom ?? 0
    }

    /// Rows of a frame at `pos` just added to the image: where they show a fixed region, the page is hidden.
    private func markCovered(rows: Range<Int>, at pos: Int) {
        let band = CGRect(x: 0, y: rows.lowerBound, width: width, height: rows.count)
        for r in fixed {
            let part = r.intersection(band)
            if !part.isEmpty { covered.append(part.offsetBy(dx: 0, dy: CGFloat(pos))) }
        }
    }

    /// Replaces covered areas that this frame, at `pos`, shows free of fixed regions within its page `rows`.
    private func uncover(with frame: CGImage, at pos: Int, rows: Range<Int>) {
        covered.removeAll { area in
            let inFrame = area.offsetBy(dx: 0, dy: CGFloat(-pos))
            guard inFrame.minY >= CGFloat(rows.lowerBound), inFrame.maxY <= CGFloat(rows.upperBound),
                  !fixed.contains(where: { $0.intersects(inFrame) }),
                  let crop = frame.cropping(to: inFrame), let image = Self.copy(crop, rows: 0..<crop.height) else { return false }
            pieces.append((Int(area.minX), Int(area.minY), image))
            return true
        }
    }

    /// Vertical shift of `cur` relative to `prev` (`prev[y + dy] ≈ cur[y]`), or nil when they do not match.
    ///
    /// Samples in `mask` (regions fixed to the viewport) are left out. Candidates are ranked by how much content fails to line up (`outliers`), which
    /// low-contrast changes such as hover highlights do not affect. Repetitive content (table
    /// rows, list items) can line up equally well at several shifts; the one closest to
    /// `predicted`, the previous frame's shift, wins such ties, since scrolling is continuous.
    static func estimateShift(prev: RowFeatures, cur: RowFeatures, predicted: Int = 0, ignoring mask: [Bool]? = nil,
                              band: Range<Int>? = nil) -> Int? {
        let h = min(prev.height, cur.height)
        let span = band?.count ?? h
        let maxShift = Int(Double(span) * 0.8)
        let minOverlap = max(span / 5, 4)
        guard let zero = RowFeatures.difference(prev: prev, cur: cur, dy: 0, step: 1, minOverlap: minOverlap, band: band) else { return nil }
        // Nothing lines up differently: not scrolled (at most a hover effect or animation).
        if zero.mean < 0.5 || zero.outliers < Self.stillOutliers { return 0 }

        var coarse: [(dy: Int, diff: RowFeatures.Difference)] = []
        var dy = -maxShift
        while dy <= maxShift {
            if let d = RowFeatures.difference(prev: prev, cur: cur, dy: dy, step: 4, minOverlap: minOverlap, ignoring: mask, band: band) {
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
                if let diff = RowFeatures.difference(prev: prev, cur: cur, dy: d, step: 1, minOverlap: minOverlap, ignoring: mask, band: band),
                   best == nil || diff.mean < best!.diff.mean {
                    best = (d, diff)
                }
            }
            return best
        }
        guard let fewest = refined.map(\.diff.outliers).min() else { return nil }
        let ties = refined.filter { $0.diff.outliers <= fewest + Self.tieOutliers }
        guard let chosen = ties.min(by: { abs($0.dy - predicted) < abs($1.dy - predicted) }) else { return nil }
        // Content lines up (a hover effect may remain), or a close match overall, or clearly the
        // best explanation when fades or fixed bars keep any shift from lining up perfectly:
        // far better than not scrolling and than every other shift.
        let others = refined.filter { abs($0.dy - chosen.dy) > 8 }.map(\.diff.outliers)
        let clearlyBest = chosen.diff.outliers < zero.outliers * 0.5 && others.allSatisfy { chosen.diff.outliers * 2 < $0 }
        guard chosen.diff.outliers < Self.matchOutliers || chosen.diff.mean < 4 || clearlyBest else { return nil }
        return chosen.dy
    }

    /// The better of two shifts, judged on the whole frame without known fixed regions; near-ties
    /// go to the one closer to `predicted`.
    static func better(_ a: Int, _ b: Int, prev: RowFeatures, cur: RowFeatures, ignoring mask: [Bool]?, predicted: Int) -> Int {
        let h = min(prev.height, cur.height)
        func outliers(_ dy: Int) -> Float {
            RowFeatures.difference(prev: prev, cur: cur, dy: dy, step: 1, minOverlap: max(h / 5, 4), ignoring: mask)?.outliers ?? .infinity
        }
        let oa = outliers(a), ob = outliers(b)
        if abs(oa - ob) <= tieOutliers { return abs(a - predicted) <= abs(b - predicted) ? a : b }
        return oa < ob ? a : b
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
                                  space: pieces.first?.image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = scale == 1 ? .none : .medium
        for piece in pieces {
            let y = CGFloat(piece.y - start) * scale
            let pw = CGFloat(piece.image.width) * scale, ph = CGFloat(piece.image.height) * scale
            ctx.draw(piece.image, in: CGRect(x: CGFloat(piece.x) * scale, y: CGFloat(h) - y - ph, width: pw, height: ph))
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
