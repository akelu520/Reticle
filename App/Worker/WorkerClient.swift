import AppKit
import ReticleCore

/// Launches ReticleWorker for memory-heavy tasks so Vision and AVFoundation
/// never stay resident in the menu-bar app. Each task gets a fresh process that
/// exits when it is done, taking its memory with it.
@MainActor
enum WorkerClient {
    enum Failure: LocalizedError {
        case missingWorker
        case crashed(Int32)
        case badResponse

        var errorDescription: String? {
            switch self {
            case .missingWorker: return "找不到 ReticleWorker，请重新安装 Reticle。"
            case let .crashed(code): return "后台进程异常退出（\(code)）。"
            case .badResponse: return "后台进程返回了无法识别的结果。"
            }
        }
    }

    private static var recording: Process?

    static var isRecording: Bool { recording?.isRunning == true }

    private static var executable: URL? {
        Bundle.main.url(forAuxiliaryExecutable: WorkerProtocol.executableName)
    }

    // MARK: - OCR

    static func recognizeText(in image: CGImage) async throws -> String {
        guard let executable else { throw Failure.missingWorker }
        let input = FileManager.default.temporaryDirectory.appendingPathComponent("reticle-ocr-\(UUID().uuidString).png")
        guard let png = ImageEncoder.png(image) else { throw Failure.badResponse }
        try png.write(to: input)
        defer { try? FileManager.default.removeItem(at: input) }

        let (status, output) = try await run(executable, [WorkerProtocol.Command.ocr.rawValue, input.path])
        guard status == 0 else { throw Failure.crashed(status) }
        guard let line = output.split(separator: 0x0A).last,
              let response = try? JSONDecoder().decode(WorkerProtocol.OCRResponse.self, from: Data(line)) else { throw Failure.badResponse }
        if let error = response.error { throw NSError(domain: "ReticleWorker", code: 1, userInfo: [NSLocalizedDescriptionKey: error]) }
        return response.text ?? ""
    }

    /// Runs the worker to completion and returns its exit status and stdout.
    private static func run(_ executable: URL, _ arguments: [String]) async throws -> (Int32, Data) {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        return try await withCheckedThrowingContinuation { continuation in
            // Read on a background queue so a large result cannot fill the pipe and block the worker.
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try process.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    continuation.resume(returning: (process.terminationStatus, data))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Recording

    /// Hands the selected region to a worker that records, previews and exports.
    static func startRecording(_ request: WorkerProtocol.RecordRequest) throws {
        guard !isRecording else { return }
        guard let executable else { throw Failure.missingWorker }
        let json = String(decoding: try JSONEncoder().encode(request), as: UTF8.self)
        let process = Process()
        process.executableURL = executable
        process.arguments = [WorkerProtocol.Command.record.rawValue, json]
        process.terminationHandler = { _ in
            DispatchQueue.main.async { recording = nil }
        }
        try process.run()
        recording = process
    }

    /// ⌥⇧R while recording: ask the worker to finish.
    static func stopRecording() {
        guard let process = recording, process.isRunning else { return }
        kill(process.processIdentifier, WorkerProtocol.stopSignal)
    }

    #if DEBUG
    /// E2E: opens the preview for `url` in a worker; returns the process so the test can wait for it.
    static func openPreview(url: URL, format: RecordingFormat, environment: [String: String]) throws -> (Process, Pipe) {
        guard let executable else { throw Failure.missingWorker }
        let process = Process()
        process.executableURL = executable
        process.arguments = [WorkerProtocol.Command.preview.rawValue, url.path, format.rawValue]
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        return (process, pipe)
    }

    static var recordingProcess: Process? { recording }
    #endif
}
