import CoreGraphics

public enum Mosaic {
    /// A pixelated copy of the whole image; mosaic marks reveal parts of it.
    ///
    /// Pure CoreGraphics: shrink with averaging, then enlarge without
    /// interpolation. Avoids CoreImage, which would bring up Metal (~20 MB).
    public static func pixelate(_ image: CGImage, blockSize: CGFloat) -> CGImage? {
        let block = max(blockSize, 2)
        let w = image.width, h = image.height
        let sw = max(Int((CGFloat(w) / block).rounded(.up)), 1)
        let sh = max(Int((CGFloat(h) / block).rounded(.up)), 1)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let small = CGContext(data: nil, width: sw, height: sh, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info) else { return nil }
        small.interpolationQuality = .high
        // Draw so each small pixel covers exactly `block` source pixels from the top-left.
        let scaledW = CGFloat(sw) * block, scaledH = CGFloat(sh) * block
        small.draw(image, in: CGRect(x: 0, y: CGFloat(sh) - CGFloat(h) / block, width: CGFloat(w) / block, height: CGFloat(h) / block))
        guard let tiny = small.makeImage(),
              let big = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info) else { return nil }
        big.interpolationQuality = .none
        big.draw(tiny, in: CGRect(x: 0, y: CGFloat(h) - scaledH, width: scaledW, height: scaledH))
        return big.makeImage()
    }
}
