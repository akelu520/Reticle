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
let size = NSScreen.main!.frame.size, scale = NSScreen.main!.backingScaleFactor
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
NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
SWIFT
swift "$OUT/make-demo.swift" "$OUT/demo.png"

set +e
RETICLE_E2E=1 \
RETICLE_DEMO_IMAGE="$PWD/$OUT/demo.png" \
RETICLE_E2E_SAVE_DIR="$PWD/$OUT/saves" \
RETICLE_E2E_HELPER="$PWD/$OUT/e2e-scroll-target" \
RETICLE_HISTORY_DIR="$PWD/$OUT/history" \
  build/dd/Build/Products/Debug/Reticle.app/Contents/MacOS/Reticle 2>/dev/null
status=$?
if [ -f "$OUT/saves/real-scroll.png" ]; then
  swift scripts/e2e-verify-scroll.swift "$OUT/saves/real-scroll.png" 40 || status=$((status + 1))
fi
echo "artifacts: $OUT/saves"
exit $status
