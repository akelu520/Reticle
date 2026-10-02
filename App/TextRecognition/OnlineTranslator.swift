import Foundation
import ReticleCore

/// Translates recognized text online: Bing Translator first, Tencent TranSmart if Bing fails.
/// Only the text being translated leaves the Mac.
@MainActor
final class OnlineTranslator {
    static let shared = OnlineTranslator()

    private let urlSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()
    private var bing: OnlineTranslation.Bing.Session?

    /// `target` is one of `TranslationLanguages.all`.
    func translate(_ text: String, to target: String) async throws -> String {
        do {
            return try await translateWithBing(text, to: target)
        } catch let primary {
            do {
                return try await fetch(OnlineTranslation.TranSmart.translateRequest(text, to: target),
                                       parse: OnlineTranslation.TranSmart.translation(from:))
            } catch {
                // Report the primary service's failure; it is the one users can act on (network).
                throw Self.describe(primary)
            }
        }
    }

    private func translateWithBing(_ text: String, to target: String) async throws -> String {
        var pieces: [String] = []
        for chunk in OnlineTranslation.chunks(of: text, limit: OnlineTranslation.Bing.limit) {
            guard !chunk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                pieces.append(chunk)
                continue
            }
            do {
                pieces.append(try await bingChunk(chunk, to: target, session: try await bingSession()))
            } catch {
                // The token may have been revoked early: start a new session once.
                bing = nil
                pieces.append(try await bingChunk(chunk, to: target, session: try await bingSession()))
            }
        }
        return pieces.joined(separator: "\n")
    }

    private func bingChunk(_ chunk: String, to target: String, session: OnlineTranslation.Bing.Session) async throws -> String {
        try await fetch(OnlineTranslation.Bing.translateRequest(chunk, to: target, session: session),
                        parse: OnlineTranslation.Bing.translation(from:))
    }

    private func bingSession() async throws -> OnlineTranslation.Bing.Session {
        if let bing, bing.expires > Date() { return bing }
        let (data, _) = try await urlSession.data(for: OnlineTranslation.Bing.pageRequest())
        guard let session = OnlineTranslation.Bing.session(fromPage: String(decoding: data, as: UTF8.self)) else {
            throw OnlineTranslation.Failure.badResponse
        }
        bing = session
        return session
    }

    private func fetch(_ request: URLRequest, parse: (Data) throws -> String) async throws -> String {
        let (data, response) = try await urlSession.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 429 {
            throw OnlineTranslation.Failure.serviceError("请求太频繁，请稍后再试")
        }
        return try parse(data)
    }

    private static func describe(_ error: Error) -> Error {
        guard let url = error as? URLError else { return error }
        switch url.code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .timedOut, .dnsLookupFailed:
            return NSError(domain: "Reticle", code: url.errorCode, userInfo: [NSLocalizedDescriptionKey: "无法连接翻译服务，请检查网络"])
        default:
            return error
        }
    }
}
