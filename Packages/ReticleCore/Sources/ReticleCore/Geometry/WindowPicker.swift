import CoreGraphics

/// Chooses the rectangle to highlight while hovering before a selection exists.
public enum WindowPicker {
    /// - Parameters:
    ///   - windows: window frames in screen-local flipped coordinates, ordered front to back.
    ///   - screen: the screen's own bounds in the same space.
    /// - Returns: the frontmost window under `point`, clipped to the screen, or the whole screen.
    public static func pick(at point: CGPoint, windows: [CGRect], screen: CGRect) -> CGRect {
        for w in windows where w.contains(point) {
            let clipped = w.intersection(screen)
            if !clipped.isNull && clipped.width >= 1 && clipped.height >= 1 { return clipped }
        }
        return screen
    }
}
