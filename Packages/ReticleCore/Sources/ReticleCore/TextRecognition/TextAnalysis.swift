import Foundation
import NaturalLanguage

public enum LinkDetector {
    /// Web links found in `text`, as ranges into it.
    public static func links(in text: String) -> [(range: NSRange, url: URL)] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        let full = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, range: full).compactMap { m in
            guard let url = m.url, url.scheme == "http" || url.scheme == "https" else { return nil }
            return (m.range, url)
        }
    }
}

/// Languages offered for translation, as BCP-47 codes with display names.
public enum TranslationLanguages {
    public static let all: [(code: String, name: String)] = [
        ("zh-Hans", "简体中文"),
        ("zh-Hant", "繁體中文"),
        ("en", "English"),
        ("ja", "日本語"),
        ("ko", "한국어"),
    ]

    /// Recognition is limited to the offered languages, so short text such as
    /// "Reticle demo" is not mistaken for an unrelated language.
    static func recognizer(for text: String) -> NLLanguageRecognizer {
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [.simplifiedChinese, .traditionalChinese, .english, .japanese, .korean]
        recognizer.processString(text)
        return recognizer
    }

    /// BCP-47 code of the dominant language, or nil when unsure.
    public static func detectedSource(for text: String) -> String? {
        let recognizer = recognizer(for: text)
        guard let language = recognizer.dominantLanguage, language != .undetermined else { return nil }
        return language.rawValue
    }

    /// Chinese text translates to English; anything else translates to Simplified Chinese.
    public static func defaultTarget(for text: String) -> String {
        switch recognizer(for: text).dominantLanguage {
        case .simplifiedChinese?, .traditionalChinese?: return "en"
        default: return "zh-Hans"
        }
    }
}
