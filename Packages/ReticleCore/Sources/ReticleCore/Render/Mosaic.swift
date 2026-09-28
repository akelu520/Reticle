import Accelerate
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

    /// A blurred copy (two tent passes ≈ Gaussian) on the CPU with Accelerate; no Metal.
    public static func blur(_ image: CGImage, radius: CGFloat) -> CGImage? {
        let w = image.width, h = image.height
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let src = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info),
              let dst = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info),
              let srcData = src.data, let dstData = dst.data else { return nil }
        src.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var a = vImage_Buffer(data: srcData, height: vImagePixelCount(h), width: vImagePixelCount(w), rowBytes: src.bytesPerRow)
        var b = vImage_Buffer(data: dstData, height: vImagePixelCount(h), width: vImagePixelCount(w), rowBytes: dst.bytesPerRow)
        // Each tent pass of size k blurs like a box of k twice; split the radius over two passes.
        let k = UInt32(max(Int(radius), 1)) | 1
        let flags = vImage_Flags(kvImageEdgeExtend)
        guard vImageTentConvolve_ARGB8888(&a, &b, nil, 0, 0, k, k, nil, flags) == kvImageNoError,
              vImageTentConvolve_ARGB8888(&b, &a, nil, 0, 0, k, k, nil, flags) == kvImageNoError else { return nil }
        return src.makeImage()
    }
}
