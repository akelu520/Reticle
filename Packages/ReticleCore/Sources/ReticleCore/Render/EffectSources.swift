import CoreGraphics

/// Full-image sources that mosaic / blur marks reveal, one per effect and strength,
/// built on first use and cached. Not thread-safe.
public final class EffectSources {
    private let base: CGImage
    private let scale: CGFloat
    private var cache: [String: CGImage] = [:]

    public init(base: CGImage, scale: CGFloat) {
        self.base = base
        self.scale = scale
    }

    /// Mosaic block edge in pixels: 2…14 pt by strength (8 pt at 50%).
    public static func blockSize(strength: CGFloat, scale: CGFloat) -> CGFloat {
        (2 + min(max(strength, 0), 1) * 12) * scale
    }

    /// Blur radius in pixels: 2…16 pt by strength.
    public static func blurRadius(strength: CGFloat, scale: CGFloat) -> CGFloat {
        (2 + min(max(strength, 0), 1) * 14) * scale
    }

    public func image(for style: Style) -> CGImage? {
        // Strengths are quantized so dragging a slider does not rebuild on every tick.
        let bucket = Int((min(max(style.strength, 0), 1) * 20).rounded())
        let key = "\(style.effect.rawValue)-\(bucket)"
        if let hit = cache[key] { return hit }
        let strength = CGFloat(bucket) / 20
        let image: CGImage?
        switch style.effect {
        case .mosaic: image = Mosaic.pixelate(base, blockSize: Self.blockSize(strength: strength, scale: scale))
        case .blur: image = Mosaic.blur(base, radius: Self.blurRadius(strength: strength, scale: scale))
        }
        cache[key] = image
        return image
    }
}
