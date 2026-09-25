import AppKit
import ReticleCore

// ReticleWorker: runs one memory-heavy task for Reticle, then exits.
// See Shared/WorkerProtocol.swift for the commands.
let arguments = Array(CommandLine.arguments.dropFirst())
guard let first = arguments.first, let command = WorkerProtocol.Command(rawValue: first) else {
    FileHandle.standardError.write(Data("usage: ReticleWorker ocr <png> | record <json> | preview <file> <mp4|gif>\n".utf8))
    exit(2)
}

switch command {
case .ocr:
    guard arguments.count == 2 else { exit(2) }
    OCRCommand.run(path: arguments[1])

case .record:
    guard arguments.count == 2,
          let request = try? JSONDecoder().decode(WorkerProtocol.RecordRequest.self, from: Data(arguments[1].utf8)),
          let format = RecordingFormat(rawValue: request.format) else { exit(2) }
    WorkerApp.run {
        guard let screen = NSScreen.withDisplayID(request.displayID) else {
            WorkerApp.fail("找不到要录制的显示器")
            return
        }
        ScreenRecorder.start(screen: screen, rect: request.rect, scale: request.scale, format: format)
    }

case .preview:
    guard arguments.count == 3, let format = RecordingFormat(rawValue: arguments[2]) else { exit(2) }
    WorkerApp.run {
        RecordingPreviewWindow.show(url: URL(fileURLWithPath: arguments[1]), format: format)
    }
}
