// Checks a real scroll capture from the E2E run against the helper's page:
// every 60-row window of the stitched image must match the page at one
// constant offset (the selection inset). A seam or duplicated strip breaks it.
//
// Usage: e2e-verify-scroll <stitched.png> <inset px>
import AppKit
import ImageIO

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

func gray(_ img: CGImage) -> (w: Int, h: Int, p: [UInt8]) {
    let ctx = CGContext(data: nil, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: img.width,
                        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
    return (img.width, img.height, Array(UnsafeBufferPointer(start: ctx.data!.assumingMemoryBound(to: UInt8.self), count: img.width * img.height)))
}

let args = CommandLine.arguments
guard args.count >= 3, let inset = Int(args[2]),
      let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
    print("usage: e2e-verify-scroll <stitched.png> <inset px> [chat|chat-up]")
    exit(2)
}
let mode = args.count > 3 ? args[3] : "page"
let s = gray(image)
let page = gray(mode == "page" || mode == "line" ? makePage(width: 1040, height: 8000) : makeChatPage(width: 1040, height: 8000))
let window = 60

func windowDiff(_ y: Int, pageY: Int) -> Double {
    var d = 0
    for dy in stride(from: 0, to: window, by: 2) {
        for x in stride(from: 0, to: s.w, by: 4) {
            d += abs(Int(s.p[(y + dy) * s.w + x]) - Int(page.p[(pageY + dy) * page.w + x + inset]))
        }
    }
    return Double(d) / Double((window / 2) * (s.w / 4))
}

// The plain page starts at the top of the page; a chat capture shows the fixed title bar and
// fade of one screen at its top and the input box, fade and button of another at its bottom,
// and (scrolling up) ends wherever the scrolling stopped: find where it sits on the page.
let skipTop = mode == "page" || mode == "line" ? 0 : 160
let skipBottom = mode == "page" ? 0 : mode == "line" ? 12 : 340
var offset = inset
if mode != "page" {
    var best = (offset: 0, d: Double.infinity)
    for o in stride(from: 0, to: page.h - s.h, by: 1) {
        let d = windowDiff(skipTop, pageY: o + skipTop)
        if d < best.d { best = (o, d) }
    }
    offset = best.offset
}
var worst = 0.0
for y in stride(from: skipTop, to: s.h - skipBottom - window, by: 50) {
    worst = max(worst, windowDiff(y, pageY: y + offset))
}
let ok = worst < 1.0 && s.h - skipBottom - skipTop > 1000
let label = mode == "page" ? "真实滚动截图" : mode == "line" ? "底边固定细线页面滚动截图" : mode == "chat" ? "深色聊天页向下滚动截图" : "深色聊天页向上滚动截图"
print("\(ok ? "✓" : "✗") \(label)逐行校验：\(s.w)×\(s.h)，最差窗口平均灰度差 \(String(format: "%.2f", worst))（< 1.0 为无断层）")
exit(ok ? 0 : 1)
