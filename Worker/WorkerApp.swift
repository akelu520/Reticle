import AppKit
import ReticleCore

/// Minimal AppKit host for the worker's windows (no Dock icon). The process
/// exits as soon as its last task window closes.
@MainActor
enum WorkerApp {
    nonisolated(unsafe) private static var signalSource: DispatchSourceSignal?

    nonisolated static func run(_ start: @escaping @MainActor () -> Void) -> Never {
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            // ⌥⇧R pressed again in Reticle stops the recording.
            signal(WorkerProtocol.stopSignal, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: WorkerProtocol.stopSignal, queue: .main)
            source.setEventHandler { MainActor.assumeIsolated { ScreenRecorder.stopCurrent() } }
            source.resume()
            signalSource = source
            DispatchQueue.main.async { MainActor.assumeIsolated { start() } }
            app.run()
        }
        exit(0)
    }

    /// Nothing left to show: exit, releasing AVFoundation and everything else.
    static func finish() {
        exit(0)
    }

    static func fail(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "录屏失败"
        alert.informativeText = message
        alert.runVisibly()
        finish()
    }
}

/// `ocr <png>`: Vision text recognition, one JSON line on stdout.
enum OCRCommand {
    static func run(path: String) -> Never {
        Task {
            var response = WorkerProtocol.OCRResponse()
            do {
                guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
                      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                let lines = try await TextRecognizer.recognize(image)
                response.lines = lines
                response.text = ReadingOrder.text(from: lines)
            } catch {
                response.error = error.localizedDescription
            }
            var data = (try? JSONEncoder().encode(response)) ?? Data("{}".utf8)
            data.append(0x0A)
            FileHandle.standardOutput.write(data)
            exit(0)
        }
        dispatchMain()
    }
}

/// `scan <png>`: text and QR detection, one `ScanResult` JSON line on stdout (`{}` on failure).
enum ScanCommand {
    static func run(path: String) -> Never {
        Task {
            var data = Data("{}".utf8)
            if let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
               let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
               let result = try? await ContentScanner.scan(image),
               let encoded = try? JSONEncoder().encode(result) {
                data = encoded
            }
            data.append(0x0A)
            FileHandle.standardOutput.write(data)
            exit(0)
        }
        dispatchMain()
    }
}
