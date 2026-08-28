import XCTest

@testable import StillpaneCore

final class SupportLinkTests: XCTestCase {
    private func queryValue(_ url: URL?, _ name: String) -> String? {
        url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
            .queryItems?.first { $0.name == name }?.value
    }

    func testBuildsIssueURLOnTheRepo() {
        let url = SupportLink.newIssueURL(repoSlug: "OWNER/stillpane", title: "Bug", body: "text")
        XCTAssertEqual(url?.host, "github.com")
        XCTAssertEqual(url?.path, "/OWNER/stillpane/issues/new")
    }

    func testRoundTripsNewlinesAndSpaces() {
        let body = "stillpane 0.1.0\nAccessibility: granted\nLatest capture: none yet"
        let url = SupportLink.newIssueURL(repoSlug: "OWNER/stillpane", title: "A bug report", body: body)
        XCTAssertEqual(queryValue(url, "title"), "A bug report")
        XCTAssertEqual(queryValue(url, "body"), body)
    }

    func testPlusSignSurvivesFormDecoding() {
        let url = SupportLink.newIssueURL(repoSlug: "o/r", title: "t", body: "left Option + right Option")
        // Encoded, not literal: a literal + reaches GitHub as a space.
        XCTAssertTrue(url?.absoluteString.contains("%2B") == true)
        XCTAssertEqual(queryValue(url, "body"), "left Option + right Option")
    }

    func testCapsTheBody() {
        let url = SupportLink.newIssueURL(
            repoSlug: "o/r", title: "t", body: String(repeating: "x", count: 50_000)
        )
        XCTAssertEqual(queryValue(url, "body")?.count, SupportLink.bodyLimit)
        XCTAssertLessThan(url?.absoluteString.count ?? .max, 8000)
    }
}
