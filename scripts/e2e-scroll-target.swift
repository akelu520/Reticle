// Helper app for Reticle's end-to-end tests: a borderless always-on-top window
// with a tall "page" that scrolls by itself, standing in for a user scrolling
// a web page. It is a separate program because Reticle excludes its own
// windows from captures.
//
// Usage: e2e-scroll-target <x> <y> <width> <height> <delay seconds> <scroll seconds> [chat | chat-up]
//
// `chat` shows a dark chat-like page with a title bar and fade fixed at the top, an input box
// and fade fixed at the bottom, and a floating button; `chat-up` scrolls it from the bottom up.
import AppKit

let mode = CommandLine.arguments.count > 7 ? CommandLine.arguments[7] : "page"
let args = CommandLine.arguments.dropFirst().prefix(6).compactMap { Double($0) }
guard args.count == 6 else { fatalError("usage: x y width height delay seconds [chat|chat-up]") }
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

/// Light text-like bars on a dark background, deterministic (same as the verifier's).
func makeChatPage(width: Int, height: Int) -> CGImage {
    var seed: UInt64 = 11
    func next() -> UInt64 {
        seed &+= 0x9E37_79B9_7F4A_7C15
        var z = seed
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        return z ^ (z >> 27)
    }
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(gray: 0.12, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    var y = 40
    while y < height - 40 {
        let heading = next() % 5 == 0
        for _ in 0..<(heading ? 1 : 1 + Int(next() % 4)) {
            var x = 60
            let end = 200 + Int(next() % UInt64(max(width - 260, 1)))
            let lh = heading ? 28 : 22
            while x < end {
                let w = 20 + Int(next() % 90)
                ctx.setFillColor(CGColor(gray: heading ? 0.95 : 0.8, alpha: 1))
                ctx.fill(CGRect(x: x, y: height - y - lh, width: min(w, end - x), height: lh))
                x += w + 10
            }
            y += lh + 22
        }
        y += 30
    }
    return ctx.makeImage()!
}

/// A vertical gradient to the page background, transparent at `clearAtTop` (or bottom).
final class FadeView: NSView {
    let clearAtTop: Bool
    init(frame: CGRect, clearAtTop: Bool) {
        self.clearAtTop = clearAtTop
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        let bg = NSColor(white: 0.12, alpha: 1)
        let gradient = NSGradient(starting: bg.withAlphaComponent(0), ending: bg)!
        gradient.draw(in: bounds, angle: clearAtTop ? -90 : 90)
    }
}

final class FlippedImageView: NSImageView {
    override var isFlipped: Bool { true }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
window.level = .floating
// Stay visible even if the user switches Spaces or a full-screen app during the run.
window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
let scroll = NSScrollView(frame: CGRect(origin: .zero, size: frame.size))
scroll.hasVerticalScroller = false
let doc = FlippedImageView(frame: CGRect(x: 0, y: 0, width: frame.width, height: pageHeight))
let pageImage = mode == "page" ? makePage(width: Int(frame.width * 2), height: Int(pageHeight * 2))
    : makeChatPage(width: Int(frame.width * 2), height: Int(pageHeight * 2))
doc.image = NSImage(cgImage: pageImage, size: CGSize(width: frame.width, height: pageHeight))
doc.imageScaling = .scaleAxesIndependently
scroll.documentView = doc
let root = NSView(frame: CGRect(origin: .zero, size: frame.size))
root.addSubview(scroll)
if mode != "page" {
    // Fixed to the window, like a chat app's title bar, input box and "scroll to bottom" button.
    let w = frame.width, h = frame.height
    let title = NSView(frame: CGRect(x: 0, y: h - 40, width: w, height: 40))
    title.wantsLayer = true
    title.layer?.backgroundColor = NSColor(white: 0.12, alpha: 1).cgColor
    let titleText = NSView(frame: CGRect(x: 20, y: 14, width: 160, height: 12))
    titleText.wantsLayer = true
    titleText.layer?.backgroundColor = NSColor(white: 0.7, alpha: 1).cgColor
    title.addSubview(titleText)
    let input = NSView(frame: CGRect(x: 0, y: 0, width: w, height: 50))
    input.wantsLayer = true
    input.layer?.backgroundColor = NSColor(white: 0.12, alpha: 1).cgColor
    let box = NSView(frame: CGRect(x: 20, y: 6, width: w - 40, height: 38))
    box.wantsLayer = true
    box.layer?.backgroundColor = NSColor(white: 0.22, alpha: 1).cgColor
    box.layer?.cornerRadius = 10
    input.addSubview(box)
    let button = NSView(frame: CGRect(x: w / 2 - 16, y: 50 + 70 + 8, width: 32, height: 32))
    button.wantsLayer = true
    button.layer?.backgroundColor = NSColor(white: 0.3, alpha: 1).cgColor
    button.layer?.cornerRadius = 16
    for v in [FadeView(frame: CGRect(x: 0, y: h - 80, width: w, height: 40), clearAtTop: false), title,
              FadeView(frame: CGRect(x: 0, y: 50, width: w, height: 70), clearAtTop: true), input, button] {
        root.addSubview(v)
    }
}
window.contentView = root
window.orderFrontRegardless()
if mode == "chat-up" {
    scroll.contentView.scroll(to: CGPoint(x: 0, y: pageHeight - frame.height))
    scroll.reflectScrolledClipView(scroll.contentView)
}

let start = Date()
// Still for `delay`, then ~180 pt/s for `seconds`, then stop.
let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { _ in
    let t = Date().timeIntervalSince(start)
    guard t > delay, t < delay + seconds else { return }
    let clip = scroll.contentView
    let step: CGFloat = mode == "chat-up" ? -6 : 6
    clip.scroll(to: CGPoint(x: 0, y: min(max(clip.bounds.minY + step, 0), pageHeight - frame.height)))
    scroll.reflectScrolledClipView(clip)
}
RunLoop.main.add(timer, forMode: .common)
app.run()
