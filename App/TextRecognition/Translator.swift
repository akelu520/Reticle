import AppKit
import SwiftUI
import Translation

/// Bridges Apple's Translation framework (macOS 15+) into AppKit. A
/// `TranslationSession` can only be obtained from SwiftUI's `.translationTask`,
/// so a 1×1 hosting view carries the request.
@available(macOS 15, *)
@MainActor
final class Translator {
    private final class Request: ObservableObject {
        @Published var configuration: TranslationSession.Configuration?
        var text = ""
        var completion: ((Result<String, Error>) -> Void)?
    }

    private struct HostView: View {
        @ObservedObject var request: Request

        var body: some View {
            Color.clear
                .frame(width: 1, height: 1)
                .translationTask(request.configuration) { session in
                    let text = request.text
                    do {
                        let response = try await session.translate(text)
                        await MainActor.run { request.completion?(.success(response.targetText)) }
                    } catch {
                        await MainActor.run { request.completion?(.failure(error)) }
                    }
                }
        }
    }

    private let request = Request()
    /// Add this to a view that is in a window; translation runs while it is attached.
    let hostView: NSView

    init() {
        hostView = NSHostingView(rootView: HostView(request: request))
        hostView.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
    }

    enum Readiness {
        case ready
        /// Supported, but the language data is not downloaded yet.
        case needsDownload
        case unsupported
    }

    /// Checks language data first: the system's download prompt cannot be relied on
    /// to appear above the full-screen capture overlay.
    static func readiness(source: String?, target: String) async -> Readiness {
        let availability = LanguageAvailability()
        let to = Locale.Language(identifier: target)
        let status: LanguageAvailability.Status
        if let source {
            status = await availability.status(from: Locale.Language(identifier: source), to: to)
        } else {
            // Unknown source: assume English, the most common case for mixed text.
            status = await availability.status(from: Locale.Language(identifier: "en"), to: to)
        }
        switch status {
        case .installed: return .ready
        case .supported: return .needsDownload
        default: return .unsupported
        }
    }

    /// Translates with automatic source detection. The system may ask to download language data.
    func translate(_ text: String, to target: String, completion: @escaping (Result<String, Error>) -> Void) {
        request.text = text
        request.completion = completion
        let config = TranslationSession.Configuration(source: nil, target: Locale.Language(identifier: target))
        if request.configuration?.target == config.target {
            request.configuration?.invalidate()
        } else {
            request.configuration = config
        }
    }
}
