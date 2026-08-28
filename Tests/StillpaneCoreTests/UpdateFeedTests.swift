import XCTest

@testable import StillpaneCore

final class UpdateFeedTests: XCTestCase {
    private func data(_ json: String) -> Data { Data(json.utf8) }

    func testParsesValidFeed() {
        let info = UpdateFeed.parse(
            data(
                #"{"version": "0.2.0", "url": "https://github.com/yayamaz/stillpane/releases/tag/v0.2.0"}"#
            ))
        XCTAssertEqual(info?.version, "0.2.0")
        XCTAssertEqual(info?.url.host, "github.com")
    }

    func testRejectsMissingFields() {
        XCTAssertNil(UpdateFeed.parse(data(#"{"version": "0.2.0"}"#)))
        XCTAssertNil(UpdateFeed.parse(data(#"{"url": "https://example.com"}"#)))
    }

    func testRejectsNonHTTPSURL() {
        XCTAssertNil(
            UpdateFeed.parse(
                data(
                    #"{"version": "0.2.0", "url": "http://example.com"}"#
                )))
        XCTAssertNil(
            UpdateFeed.parse(
                data(
                    #"{"version": "0.2.0", "url": "file:///etc/passwd"}"#
                )))
    }

    func testRejectsJunkVersion() {
        XCTAssertNil(
            UpdateFeed.parse(
                data(
                    #"{"version": "latest", "url": "https://example.com"}"#
                )))
        XCTAssertNil(
            UpdateFeed.parse(
                data(
                    #"{"version": "1..0", "url": "https://example.com"}"#
                )))
        XCTAssertNil(
            UpdateFeed.parse(
                data(
                    #"{"version": "", "url": "https://example.com"}"#
                )))
    }

    /// The URL contract: exactly this repository's release page for exactly
    /// the announced version, with nothing riding along.
    func testRejectsAnyOtherDestination() {
        let cases = [
            // Another host, lookalike repositories, non-release pages.
            #"{"version": "0.2.0", "url": "https://example.com/yayamaz/stillpane/releases/tag/v0.2.0"}"#,
            #"{"version": "0.2.0", "url": "https://github.com/evil/stillpane/releases/tag/v0.2.0"}"#,
            #"{"version": "0.2.0", "url": "https://github.com/yayamaz/stillpane-evil/releases/tag/v0.2.0"}"#,
            #"{"version": "0.2.0", "url": "https://github.com/yayamaz/stillpane/releases/latest"}"#,
            #"{"version": "0.2.0", "url": "https://github.com/yayamaz/stillpane"}"#,
            // Userinfo tricks, ports, queries, fragments.
            #"{"version": "0.2.0", "url": "https://github.com@evil.com/yayamaz/stillpane/releases/tag/v0.2.0"}"#,
            #"{"version": "0.2.0", "url": "https://user:pw@github.com/yayamaz/stillpane/releases/tag/v0.2.0"}"#,
            #"{"version": "0.2.0", "url": "https://github.com:8443/yayamaz/stillpane/releases/tag/v0.2.0"}"#,
            #"{"version": "0.2.0", "url": "https://github.com/yayamaz/stillpane/releases/tag/v0.2.0?next=https://evil.com"}"#,
            #"{"version": "0.2.0", "url": "https://github.com/yayamaz/stillpane/releases/tag/v0.2.0#frag"}"#,
            // A URL announcing one version while the feed says another.
            #"{"version": "0.2.0", "url": "https://github.com/yayamaz/stillpane/releases/tag/v0.3.0"}"#,
            // Path traversal back out of the release tree.
            #"{"version": "0.2.0", "url": "https://github.com/yayamaz/stillpane/releases/tag/v0.2.0/../../../evil"}"#,
        ]
        for json in cases {
            XCTAssertNil(UpdateFeed.parse(data(json)), json)
        }
    }

    func testRejectsNonJSON() {
        XCTAssertNil(UpdateFeed.parse(data("<html>error page</html>")))
        XCTAssertNil(UpdateFeed.parse(Data()))
        XCTAssertNil(UpdateFeed.parse(data(#"["0.2.0"]"#)))
    }

    func testIsNewer() {
        XCTAssertTrue(UpdateFeed.isNewer("0.2.0", than: "0.1.0"))
        XCTAssertTrue(UpdateFeed.isNewer("1.0.0", than: "0.9.9"))
        XCTAssertTrue(UpdateFeed.isNewer("0.10.0", than: "0.9.0"))
        XCTAssertTrue(UpdateFeed.isNewer("1.0.1", than: "1.0"))
        XCTAssertFalse(UpdateFeed.isNewer("0.1.0", than: "0.1.0"))
        XCTAssertFalse(UpdateFeed.isNewer("1.0", than: "1.0.0"))
        XCTAssertFalse(UpdateFeed.isNewer("0.1.0", than: "0.2.0"))
        XCTAssertFalse(UpdateFeed.isNewer("0.9.9", than: "1.0.0"))
    }
}
