import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageEncoder {
    public static func png(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}

public enum FileNaming {
    public static func screenshotName(for date: Date, timeZone: TimeZone = .current) -> String {
        name(for: date, extension: "png", timeZone: timeZone)
    }

    /// `Reticle_yyyy-MM-dd_HH-mm-ss.<ext>`
    public static func name(for date: Date, extension ext: String, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return "Reticle_\(f.string(from: date)).\(ext)"
    }
}
