#if DEBUG
import AppKit
import ScreenCaptureKit
import UniformTypeIdentifiers

/// Local-only debugging aid (not committed): executes commands from a file, one per line,
/// posting real input events and taking screenshots, so a reference UI can be studied step by step.
/// Coordinates are CG global points (top-left of the primary display).
///
///   snap NAME | move X Y | click X Y [N] | down X Y | drag X Y | up X Y | key CODE [cmd,shift,opt,ctrl] | wait MS | quit
@MainActor
enum RemoteControl {
    private static var offset = 0
    private static var last = CGPoint.zero
    /// One command at a time, so `wait` really delays what follows.
    private static var busy = false
    /// Set by a failed `guard`: every later command is skipped, so nothing lands on the wrong UI.
    private static var aborted = false

    static func run(commands: URL, out: URL) {
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        log(out, "ready AX=\(AXIsProcessTrusted()) SC=\(CGPreflightScreenCaptureAccess())")
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            MainActor.assumeIsolated { poll(commands, out) }
        }
    }

    private static func poll(_ commands: URL, _ out: URL) {
        guard !busy, let text = try? String(contentsOf: commands, encoding: .utf8) else { return }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.count - 1 > offset else { return } // only complete lines
        let line = lines[offset].trimmingCharacters(in: .whitespaces)
        offset += 1
        guard !line.isEmpty else { return }
        busy = true
        Task { @MainActor in
            await execute(line, out)
            busy = false
        }
    }

    private static func execute(_ line: String, _ out: URL) async {
        let p = line.split(separator: " ").map(String.init)
        if aborted && p[0] != "quit" && p[0] != "snap" && p[0] != "reset" {
            log(out, "ok skipped \(line)")
            return
        }
        func pt(_ i: Int) -> CGPoint { CGPoint(x: Double(p[i]) ?? 0, y: Double(p[i + 1]) ?? 0) }
        switch p[0] {
        case "snap":
            await snap(p.count > 1 ? p[1] : "snap", out)
        case "move":
            mouse(.mouseMoved, pt(1))
        case "click":
            let n = p.count > 3 ? Int(p[3]) ?? 1 : 1
            for i in 1...n {
                mouse(.leftMouseDown, pt(1), clicks: i)
                mouse(.leftMouseUp, pt(1), clicks: i)
            }
        case "down":
            mouse(.leftMouseDown, pt(1))
        case "drag":
            let from = last, to = pt(1)
            for i in 1...12 {
                let t = CGFloat(i) / 12
                mouse(.leftMouseDragged, CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t))
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
        case "up":
            mouse(.leftMouseUp, pt(1))
        case "key":
            var flags: CGEventFlags = []
            if p.count > 2 {
                for f in p[2].split(separator: ",") {
                    switch f {
                    case "cmd": flags.insert(.maskCommand)
                    case "shift": flags.insert(.maskShift)
                    case "opt": flags.insert(.maskAlternate)
                    case "ctrl": flags.insert(.maskControl)
                    default: break
                    }
                }
            }
            // Press modifiers as real keys first; many global shortcuts check them.
            let code = CGKeyCode(p[1]) ?? 0
            let mods: [(CGEventFlags, CGKeyCode)] = [(.maskCommand, 55), (.maskShift, 56), (.maskAlternate, 58), (.maskControl, 59)]
            var held: CGEventFlags = []
            for (flag, key) in mods where flags.contains(flag) {
                held.insert(flag)
                let e = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: true)
                e?.flags = held
                e?.post(tap: .cghidEventTap)
                try? await Task.sleep(nanoseconds: 30_000_000)
            }
            for down in [true, false] {
                let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)
                e?.flags = held
                e?.post(tap: .cghidEventTap)
                try? await Task.sleep(nanoseconds: 30_000_000)
            }
            for (flag, key) in mods.reversed() where held.contains(flag) {
                held.remove(flag)
                let e = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: false)
                e?.flags = held
                e?.post(tap: .cghidEventTap)
                try? await Task.sleep(nanoseconds: 30_000_000)
            }
        case "guard":
            // guard OWNER LAYER: require an on-screen window of that owner at that layer.
            let owner = p.count > 1 ? p[1] : "", layer = p.count > 2 ? Int(p[2]) ?? 0 : 0
            let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
            let present = list.contains { ($0[kCGWindowOwnerName as String] as? String)?.contains(owner) == true && ($0[kCGWindowLayer as String] as? Int) == layer }
            if !present {
                aborted = true
                log(out, "ABORT guard failed: \(owner) layer \(layer) not on screen")
            }
        case "reset":
            aborted = false
        case "wait":
            try? await Task.sleep(nanoseconds: UInt64((Double(p[1]) ?? 0) * 1_000_000))
        case "quit":
            log(out, "bye")
            exit(0)
        default:
            break
        }
        log(out, "ok \(line)")
    }

    private static func mouse(_ type: CGEventType, _ p: CGPoint, clicks: Int = 1) {
        let button: CGMouseButton = .left
        let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: button)
        e?.setIntegerValueField(.mouseEventClickState, value: Int64(clicks))
        e?.post(tap: .cghidEventTap)
        last = p
    }

    /// Captures the primary display (nothing excluded) to NAME.png.
    private static func snap(_ name: String, _ out: URL) async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let screen = NSScreen.screens.first, let id = screen.displayID,
                  let display = content.displays.first(where: { $0.displayID == id }) else { return }
            let config = SCStreamConfiguration()
            config.width = Int(screen.frame.width * screen.backingScaleFactor)
            config.height = Int(screen.frame.height * screen.backingScaleFactor)
            config.showsCursor = true
            let image = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(display: display, excludingWindows: []), configuration: config)
            let url = out.appendingPathComponent("\(name).png")
            if let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) {
                CGImageDestinationAddImage(dest, image, nil)
                CGImageDestinationFinalize(dest)
            }
        } catch {
            log(out, "snap failed: \(error.localizedDescription)")
        }
    }

    private static func log(_ out: URL, _ s: String) {
        let url = out.appendingPathComponent("log.txt")
        let line = Data((s + "\n").utf8)
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(line); try? h.close()
        } else {
            try? line.write(to: url)
        }
    }
}
#endif
