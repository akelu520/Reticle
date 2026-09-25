import CoreGraphics

/// The single place that converts between coordinate systems.
///
/// - CG global: origin at the primary display's top-left, y down (CGWindowList, ScreenCaptureKit).
/// - AppKit global: origin at the primary display's bottom-left, y up (NSScreen.frame).
/// - Screen-local flipped: origin at a given screen's top-left, y down (overlay views).
public enum CoordinateSpace {
    public static func localFlipped(fromCGGlobal r: CGRect, screenFrame: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: r.minX - screenFrame.minX,
               y: r.minY + screenFrame.maxY - primaryHeight,
               width: r.width, height: r.height)
    }

    /// Screen-local flipped rect → AppKit global rect (for placing windows).
    public static func appKitGlobal(fromLocalFlipped r: CGRect, screenFrame: CGRect) -> CGRect {
        CGRect(x: screenFrame.minX + r.minX, y: screenFrame.maxY - r.maxY, width: r.width, height: r.height)
    }

    /// Converts a rectangle in points to pixels, rounding outward so no content is lost.
    /// A tiny epsilon absorbs floating-point noise (e.g. 756 × 2 = 1512.0000000001) so it
    /// does not add a whole extra pixel.
    public static func pixelRect(fromPoints r: CGRect, scale: CGFloat) -> CGRect {
        let e: CGFloat = 1e-6
        let minX = (r.minX * scale + e).rounded(.down)
        let minY = (r.minY * scale + e).rounded(.down)
        let maxX = (r.maxX * scale - e).rounded(.up)
        let maxY = (r.maxY * scale - e).rounded(.up)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
