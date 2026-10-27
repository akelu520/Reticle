import CoreGraphics
import Foundation

/// The direction a scroll capture grows in.
public enum ScrollAxis: Sendable, Equatable {
    case vertical
    case horizontal
}

/// Stitches a scroll capture in whichever direction the page scrolls.
///
/// A horizontal scroll is a vertical one with rows and columns swapped, so horizontal frames go
/// to a second `ScrollStitcher` transposed, and its result is transposed back — everything the
/// vertical stitcher handles (fixed bars and fades, floating buttons, repetitive content) works
/// sideways too: a sidebar fixed on the left is what a sticky header is vertically.
///
/// Until the direction is clear, frames go to both; two movements one way (and none the other)
/// decide it.
public final class ScrollCaptureStitcher {
    public private(set) var axis: ScrollAxis?
    private let vertical: ScrollStitcher
    private let horizontal: ScrollStitcher
    private var votes = (vertical: 0, horizontal: 0)

    public init(maxLength: Int = 30000) {
        vertical = ScrollStitcher(maxHeight: maxLength)
        horizontal = ScrollStitcher(maxHeight: maxLength)
    }

    /// Length along the scroll direction (the height while undecided).
    public var length: Int {
        axis == .horizontal ? horizontal.height : vertical.height
    }

    public func add(_ frame: CGImage) -> ScrollStitcher.Update {
        switch axis {
        case .vertical?:
            return vertical.add(frame)
        case .horizontal?:
            guard let t = ImageTranspose.transposed(frame) else { return .mismatch }
            return horizontal.add(t)
        case nil:
            let v = vertical.add(frame)
            let h = ImageTranspose.transposed(frame).map { horizontal.add($0) } ?? .mismatch
            switch (Self.moved(v), Self.moved(h)) {
            case (true, false): votes.vertical += 1
            case (false, true): votes.horizontal += 1
            default: break
            }
            if votes.vertical >= 2 {
                axis = .vertical
            } else if votes.horizontal >= 2 {
                axis = .horizontal
                return h
            }
            return Self.moved(h) && !Self.moved(v) ? h : v
        }
    }

    private static func moved(_ u: ScrollStitcher.Update) -> Bool {
        if case .moved = u { return true }
        return false
    }

    /// The long image, `scale` times its full size.
    public func compose(scale: CGFloat = 1) -> CGImage? {
        guard axis == .horizontal else { return vertical.compose(scale: scale) }
        return horizontal.compose(scale: scale).flatMap(ImageTranspose.transposed)
    }
}

/// Swaps rows and columns: pixel (x, y) moves to (y, x). Its own inverse.
enum ImageTranspose {
    static func transposed(_ image: CGImage) -> CGImage? {
        let w = image.width, h = image.height
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        guard w > 0, h > 0,
              let src = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space, bitmapInfo: info),
              let dst = CGContext(data: nil, width: h, height: w, bitsPerComponent: 8, bytesPerRow: h * 4, space: space, bitmapInfo: info),
              let sData = src.data, let dData = dst.data else { return nil }
        src.interpolationQuality = .none
        src.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let s = sData.bindMemory(to: UInt32.self, capacity: w * h)
        let d = dData.bindMemory(to: UInt32.self, capacity: w * h)
        // In tiles, so both images are read and written in cache-sized pieces.
        let tile = 32
        for y0 in stride(from: 0, to: h, by: tile) {
            for x0 in stride(from: 0, to: w, by: tile) {
                for y in y0..<min(y0 + tile, h) {
                    for x in x0..<min(x0 + tile, w) { d[x * h + y] = s[y * w + x] }
                }
            }
        }
        return dst.makeImage()
    }
}
