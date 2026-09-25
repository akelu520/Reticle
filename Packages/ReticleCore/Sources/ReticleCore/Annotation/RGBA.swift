import CoreGraphics

/// An sRGB color that is Codable and comparable, unlike CGColor.
public struct RGBA: Codable, Equatable, Hashable, Sendable {
    public var r: CGFloat
    public var g: CGFloat
    public var b: CGFloat
    public var a: CGFloat

    public init(r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    public init(hex: UInt32) {
        self.init(r: CGFloat((hex >> 16) & 0xFF) / 255, g: CGFloat((hex >> 8) & 0xFF) / 255, b: CGFloat(hex & 0xFF) / 255)
    }

    public var cgColor: CGColor {
        CGColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    public func withAlpha(_ alpha: CGFloat) -> RGBA {
        RGBA(r: r, g: g, b: b, a: alpha)
    }

    /// Perceived brightness, used to pick readable text on a colored bubble.
    public var isLight: Bool {
        0.299 * r + 0.587 * g + 0.114 * b > 0.7
    }

    public static let red = RGBA(hex: 0xF54A45)
    public static let orange = RGBA(hex: 0xFF8800)
    public static let yellow = RGBA(hex: 0xFFC60A)
    public static let green = RGBA(hex: 0x34C724)
    public static let blue = RGBA(hex: 0x3370FF)
    public static let black = RGBA(hex: 0x1F2329)
    public static let white = RGBA(hex: 0xFFFFFF)

    /// The 7-color palette shown in the sub toolbar.
    public static let palette: [RGBA] = [.red, .orange, .yellow, .green, .blue, .black, .white]
}
