import Foundation

/// Requests and responses for the online translation services, without the networking:
/// Bing Translator's web endpoint (primary) and Tencent TranSmart (fallback). Both work
/// without an account and are reachable from mainland China.
public enum OnlineTranslation {
    public enum Failure: LocalizedError, Equatable {
        case badResponse
        case serviceError(String)

        public var errorDescription: String? {
            switch self {
            case .badResponse: "翻译服务返回了无法识别的结果"
            case let .serviceError(message): "翻译服务出错：\(message)"
            }
        }
    }

    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0 Safari/537.36"

    /// Splits `text` into pieces of at most `limit` characters at line breaks, so that joining
    /// the pieces with "\n" gives back the text. A single line longer than `limit` is cut, and
    /// comes back broken across lines.
    public static func chunks(of text: String, limit: Int) -> [String] {
        var pieces: [String] = []
        var current = ""
        for line in text.components(separatedBy: "\n") {
            // A single overlong line is cut at the limit.
            var rest = Substring(line)
            var parts: [Substring] = []
            while rest.count > limit {
                parts.append(rest.prefix(limit))
                rest = rest.dropFirst(limit)
            }
            parts.append(rest)
            for (i, part) in parts.enumerated() {
                let joiner = i == 0 ? "\n" : ""
                if current.isEmpty, pieces.isEmpty || i > 0 {
                    current = String(part)
                } else if current.count + joiner.count + part.count <= limit {
                    current += joiner + part
                } else {
                    pieces.append(current)
                    current = String(part)
                }
            }
        }
        pieces.append(current)
        return pieces
    }

    // MARK: - Bing

    public enum Bing {
        /// The web endpoint accepts at most 1000 characters per request.
        public static let limit = 1000

        /// Parameters the translator page hands its own scripts, needed for each request.
        public struct Session: Equatable, Sendable {
            public var ig: String
            public var iid: String
            public var key: String
            public var token: String
            /// When the token stops working.
            public var expires: Date
        }

        public static let pageURL = URL(string: "https://www.bing.com/translator")!

        public static func pageRequest() -> URLRequest {
            var r = URLRequest(url: pageURL)
            r.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            return r
        }

        /// Reads the session from the translator page's HTML.
        public static func session(fromPage html: String, now: Date = Date()) -> Session? {
            guard let ig = firstMatch(#"IG:"([A-Za-z0-9]+)""#, in: html),
                  let iid = firstMatch(#"data-iid="(translator\.[0-9]+)""#, in: html),
                  let params = firstMatch(#"params_AbusePreventionHelper\s*=\s*\[([^\]]+)\]"#, in: html) else { return nil }
            let fields = params.split(separator: ",").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\" ")) }
            guard fields.count >= 3, let lifetime = Double(fields[2]) else { return nil }
            // Renew a minute early.
            return Session(ig: ig, iid: iid, key: fields[0], token: fields[1], expires: now.addingTimeInterval(lifetime / 1000 - 60))
        }

        /// Our language codes are Bing's ("zh-Hans", "en", …).
        public static func translateRequest(_ text: String, to target: String, session: Session) -> URLRequest {
            var components = URLComponents(string: "https://www.bing.com/ttranslatev3")!
            components.queryItems = [URLQueryItem(name: "isVertical", value: "1"), URLQueryItem(name: "IG", value: session.ig),
                                     URLQueryItem(name: "IID", value: session.iid)]
            var r = URLRequest(url: components.url!)
            r.httpMethod = "POST"
            r.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            r.httpBody = formBody(["fromLang": "auto-detect", "to": target, "text": text, "token": session.token, "key": session.key])
            return r
        }

        /// The translated text from a `ttranslatev3` response.
        public static func translation(from data: Data) throws -> String {
            let json = try? JSONSerialization.jsonObject(with: data)
            if let results = json as? [[String: Any]],
               let translations = results.first?["translations"] as? [[String: Any]],
               let text = translations.first?["text"] as? String {
                return text
            }
            if let error = json as? [String: Any], let message = error["errorMessage"] as? String ?? (error["error"] as? [String: Any])?["message"] as? String {
                throw Failure.serviceError(message)
            }
            throw Failure.badResponse
        }
    }

    // MARK: - TranSmart

    public enum TranSmart {
        static let url = URL(string: "https://transmart.qq.com/api/imt")!

        /// TranSmart's codes for ours.
        public static func language(_ code: String) -> String {
            switch code {
            case "zh-Hans": "zh"
            case "zh-Hant": "zh-TW"
            default: code
            }
        }

        /// One entry per line; the service translates them separately and keeps their order.
        public static func translateRequest(_ text: String, to target: String) -> URLRequest {
            var r = URLRequest(url: url)
            r.httpMethod = "POST"
            r.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body: [String: Any] = [
                "header": ["fn": "auto_translation", "client_key": "browser-chrome-129.0.0-Mac OS-\(UUID().uuidString)-\(Int(Date().timeIntervalSince1970 * 1000))"],
                "type": "plain",
                "model_category": "normal",
                "source": ["lang": "auto", "text_list": text.components(separatedBy: "\n")],
                "target": ["lang": language(target)],
            ]
            r.httpBody = try? JSONSerialization.data(withJSONObject: body)
            return r
        }

        public static func translation(from data: Data) throws -> String {
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure.badResponse }
            if let lines = json["auto_translation"] as? [String] { return lines.joined(separator: "\n") }
            if let header = json["header"] as? [String: Any], let code = header["ret_code"] as? String, code != "succ" {
                throw Failure.serviceError(code)
            }
            throw Failure.badResponse
        }
    }

    // MARK: - Helpers

    static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), m.numberOfRanges > 1,
              let range = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    static func formBody(_ fields: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return Data(fields.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&").utf8)
    }
}
