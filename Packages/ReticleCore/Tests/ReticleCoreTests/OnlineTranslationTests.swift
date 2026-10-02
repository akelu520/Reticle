import XCTest
@testable import ReticleCore

final class OnlineTranslationTests: XCTestCase {
    func testBingSessionFromPage() throws {
        let html = #"<div id="rich_tta" data-iid="translator.5023"></div><script>_G={IG:"B6D36F4516554F7F8AE1C506954251EC",EF:{}};var params_AbusePreventionHelper = [1790927053024,"UNmUCwg6vfMra_jmPkrQEA2M26HVLXms",3600000];</script>"#
        let now = Date(timeIntervalSince1970: 1000)
        let s = try XCTUnwrap(OnlineTranslation.Bing.session(fromPage: html, now: now))
        XCTAssertEqual(s.ig, "B6D36F4516554F7F8AE1C506954251EC")
        XCTAssertEqual(s.iid, "translator.5023")
        XCTAssertEqual(s.key, "1790927053024")
        XCTAssertEqual(s.token, "UNmUCwg6vfMra_jmPkrQEA2M26HVLXms")
        XCTAssertEqual(s.expires, now.addingTimeInterval(3600 - 60))
        XCTAssertNil(OnlineTranslation.Bing.session(fromPage: "<html>captcha</html>"))
    }

    func testBingRequestIsAForm() throws {
        let s = OnlineTranslation.Bing.Session(ig: "IG1", iid: "translator.1", key: "123", token: "t&k", expires: .distantFuture)
        let r = OnlineTranslation.Bing.translateRequest("a b\n中文", to: "zh-Hans", session: s)
        XCTAssertEqual(r.httpMethod, "POST")
        XCTAssertEqual(r.url?.absoluteString, "https://www.bing.com/ttranslatev3?isVertical=1&IG=IG1&IID=translator.1")
        let body = String(decoding: try XCTUnwrap(r.httpBody), as: UTF8.self)
        XCTAssertEqual(body, "fromLang=auto-detect&key=123&text=a%20b%0A%E4%B8%AD%E6%96%87&to=zh-Hans&token=t%26k")
    }

    func testBingResponses() throws {
        let ok = Data(#"[{"translations":[{"text":"你好，世界\n第二行","to":"zh-Hans"}],"detectedLanguage":{"language":"en"}}]"#.utf8)
        XCTAssertEqual(try OnlineTranslation.Bing.translation(from: ok), "你好，世界\n第二行")
        let err = Data(#"{"statusCode":400,"errorMessage":"Invalid token"}"#.utf8)
        XCTAssertThrowsError(try OnlineTranslation.Bing.translation(from: err)) {
            XCTAssertEqual($0 as? OnlineTranslation.Failure, .serviceError("Invalid token"))
        }
        XCTAssertThrowsError(try OnlineTranslation.Bing.translation(from: Data("<html>".utf8)))
    }

    func testTranSmart() throws {
        XCTAssertEqual(OnlineTranslation.TranSmart.language("zh-Hans"), "zh")
        XCTAssertEqual(OnlineTranslation.TranSmart.language("zh-Hant"), "zh-TW")
        XCTAssertEqual(OnlineTranslation.TranSmart.language("ja"), "ja")
        let r = OnlineTranslation.TranSmart.translateRequest("one\ntwo", to: "zh-Hans")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(r.httpBody)) as? [String: Any])
        XCTAssertEqual((body["source"] as? [String: Any])?["text_list"] as? [String], ["one", "two"])
        XCTAssertEqual((body["target"] as? [String: Any])?["lang"] as? String, "zh")
        let ok = Data(#"{"header":{"ret_code":"succ"},"auto_translation":["一","二"]}"#.utf8)
        XCTAssertEqual(try OnlineTranslation.TranSmart.translation(from: ok), "一\n二")
    }

    func testChunksSplitOnLinesAndRejoin() {
        let text = (1...30).map { "line \($0) " + String(repeating: "x", count: 60) }.joined(separator: "\n")
        let pieces = OnlineTranslation.chunks(of: text, limit: 1000)
        XCTAssertGreaterThan(pieces.count, 1)
        XCTAssertTrue(pieces.allSatisfy { $0.count <= 1000 })
        XCTAssertEqual(pieces.joined(separator: "\n"), text)
        XCTAssertEqual(OnlineTranslation.chunks(of: "short", limit: 1000), ["short"])
        XCTAssertEqual(OnlineTranslation.chunks(of: "a\n\nb", limit: 1000), ["a\n\nb"], "blank lines survive")
    }

    func testOverlongLineIsCut() {
        let line = String(repeating: "y", count: 2500)
        let pieces = OnlineTranslation.chunks(of: line, limit: 1000)
        XCTAssertEqual(pieces.map(\.count), [1000, 1000, 500])
    }
}
