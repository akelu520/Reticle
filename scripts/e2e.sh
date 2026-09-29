#!/usr/bin/env bash
# Builds Reticle (Debug) and the scroll-target helper, then runs the in-app
# end-to-end tests. Needs the screen-recording permission for the real-screen
# section; without it that section is skipped. Exit code = number of failures.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=build/e2e
rm -rf "$OUT/saves" "$OUT/history"
mkdir -p "$OUT/saves"
xcodegen generate --quiet
xcodebuild -project Reticle.xcodeproj -scheme Reticle -configuration Debug -derivedDataPath build/dd build | tail -1
swiftc -O scripts/e2e-scroll-target.swift -o "$OUT/e2e-scroll-target"

# A static demo screen for the deterministic sections.
cat > "$OUT/make-demo.swift" <<'SWIFT'
import AppKit
import CoreImage
// The primary display, same as the app's demo mode.
let size = NSScreen.screens[0].frame.size, scale = NSScreen.screens[0].backingScaleFactor
let w = Int(size.width * scale), h = Int(size.height * scale)
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                           isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = size
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSColor(white: 0.92, alpha: 1).setFill(); NSRect(origin: .zero, size: size).fill()
NSColor.systemRed.setFill(); NSRect(x: 0, y: size.height - 150, width: 300, height: 150).fill()
let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 60), .foregroundColor: NSColor.black]
("TOP LEFT" as NSString).draw(at: NSPoint(x: 325, y: size.height - 100), withAttributes: attrs)
("Reticle demo" as NSString).draw(at: NSPoint(x: size.width * 0.3, y: size.height / 2), withAttributes: attrs)
// A QR code in the lower right, for 识别二维码.
let qr = CIFilter(name: "CIQRCodeGenerator")!
qr.setValue(Data("https://github.com/akelu520/Reticle".utf8), forKey: "inputMessage")
let code = qr.outputImage!.transformed(by: CGAffineTransform(scaleX: 7, y: 7))
NSColor.white.setFill(); NSRect(x: size.width - 300, y: 60, width: 240, height: 240).fill()
NSImage(cgImage: CIContext().createCGImage(code, from: code.extent)!, size: .zero)
  .draw(in: NSRect(x: size.width - 280, y: 80, width: 200, height: 200))
NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
SWIFT
swift "$OUT/make-demo.swift" "$OUT/demo.png"

set +e
# Launch through LaunchServices so Reticle, not the terminal, is the process
# that screen-recording permission is checked against.
LOG="$OUT/run.log"
: > "$LOG"
open -n -W --stdout "$LOG" --stderr /dev/null \
  --env RETICLE_E2E=1 \
  --env RETICLE_DEMO_IMAGE="$PWD/$OUT/demo.png" \
  --env RETICLE_E2E_SAVE_DIR="$PWD/$OUT/saves" \
  --env RETICLE_E2E_HELPER="$PWD/$OUT/e2e-scroll-target" \
  --env RETICLE_HISTORY_DIR="$PWD/$OUT/history" \
  ${RETICLE_E2E_ONLY:+--env RETICLE_E2E_ONLY="$RETICLE_E2E_ONLY"} \
  ${RETICLE_E2E_HOLD:+--env RETICLE_E2E_HOLD="$RETICLE_E2E_HOLD"} \
  build/dd/Build/Products/Debug/Reticle.app
cat "$LOG"
# `open -W` does not pass the exit status through; the summary line does.
if grep -qE '^== 结果：([0-9]+)/\1 通过' "$LOG"; then status=0; else status=1; fi
if [ -f "$OUT/saves/real-scroll.png" ]; then
  swift scripts/e2e-verify-scroll.swift "$OUT/saves/real-scroll.png" 40 || status=$((status + 1))
fi
echo "artifacts: $OUT/saves"
exit $status
