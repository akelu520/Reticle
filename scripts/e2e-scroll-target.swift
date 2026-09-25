// Helper app for Reticle's end-to-end tests: a borderless always-on-top window
// with a tall "page" that scrolls by itself, standing in for a user scrolling
// a web page. It is a separate program because Reticle excludes its own
// windows from captures.
//
// Usage: e2e-scroll-target <x> <y> <width> <height> <delay seconds> <scroll seconds>
import AppKit

let args = CommandLine.arguments.dropFirst().compactMap { Double($0) }
guard args.count == 6 else { fatalError("usage: x y width height delay seconds") }
let frame = CGRect(x: args[0], y: args[1], width: args[2], height: args[3])
let delay = args[4], seconds = args[5]
let pageHeight: CGFloat = 4000

/// Text-like gray bars on white, deterministic.
func makePage(width: Int, height: Int) -> CGImage {
    var seed: UInt64 = 7
    func next() -> UInt64 {
        seed &+= 0x9E37_79B9_7F4A_7C15
        var z = seed
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        return z ^ (z >> 27)
    }
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    var y = 0
    while y < height {
        let lh = 12 + Int(next() % 20)
        var x = 16
        while x < width - 16 {
            let w = 8 + Int(next() % 80)
            ctx.setFillColor(CGColor(gray: CGFloat(next() % 200) / 255, alpha: 1))
            ctx.fill(CGRect(x: x, y: height - y - lh, width: min(w, width - 16 - x), height: lh))
            x += w + 6 + Int(next() % 12)
        }
        y += lh + 8 + Int(next() % 16)
    }
    return ctx.makeImage()!
}

final class FlippedImageView: NSImageView {
    override var isFlipped: Bool { true }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
window.level = .floating
let scroll = NSScrollView(frame: CGRect(origin: .zero, size: frame.size))
scroll.hasVerticalScroller = false
let doc = FlippedImageView(frame: CGRect(x: 0, y: 0, width: frame.width, height: pageHeight))
doc.image = NSImage(cgImage: makePage(width: Int(frame.width * 2), height: Int(pageHeight * 2)), size: CGSize(width: frame.width, height: pageHeight))
doc.imageScaling = .scaleAxesIndependently
scroll.documentView = doc
window.contentView = scroll
window.orderFrontRegardless()

let start = Date()
// Still for `delay`, then ~180 pt/s for `seconds`, then stop.
let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { _ in
    let t = Date().timeIntervalSince(start)
    guard t > delay, t < delay + seconds else { return }
    let clip = scroll.contentView
    clip.scroll(to: CGPoint(x: 0, y: min(clip.bounds.minY + 6, pageHeight - frame.height)))
    scroll.reflectScrolledClipView(clip)
}
RunLoop.main.add(timer, forMode: .common)
app.run()
