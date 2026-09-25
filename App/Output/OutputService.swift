import AppKit
import ReticleCore

enum OutputService {
    enum Failure: LocalizedError {
        case encode
        var errorDescription: String? { "无法生成图片数据。" }
    }

    /// Writes PNG plus TIFF so every kind of app can paste it.
    static func copyToPasteboard(_ image: CGImage) -> Bool {
        guard let png = ImageEncoder.png(image) else { return false }
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        if let tiff = NSBitmapImageRep(cgImage: image).tiffRepresentation {
            item.setData(tiff, forType: .tiff)
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        return pb.writeObjects([item])
    }

    static func write(_ image: CGImage, to url: URL) throws {
        guard let png = ImageEncoder.png(image) else { throw Failure.encode }
        try png.write(to: url, options: .atomic)
    }
}
