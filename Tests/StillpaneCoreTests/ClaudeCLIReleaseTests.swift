import Foundation
import Testing

@testable import StillpaneCore

@Suite("ClaudeCLIRelease")
struct ClaudeCLIReleaseTests {
    // MARK: - Version endpoint

    @Test func acceptsPlainVersion() {
        #expect(ClaudeCLIRelease.version(fromLatest: "2.1.251\n") == "2.1.251")
    }

    @Test func acceptsPrereleaseSuffix() {
        #expect(ClaudeCLIRelease.version(fromLatest: "2.2.0-beta.1") == "2.2.0-beta.1")
    }

    @Test func rejectsErrorPage() {
        #expect(ClaudeCLIRelease.version(fromLatest: "<html><body>blocked</body></html>") == nil)
    }

    @Test func rejectsEmpty() {
        #expect(ClaudeCLIRelease.version(fromLatest: "") == nil)
        #expect(ClaudeCLIRelease.version(fromLatest: "   \n") == nil)
    }

    @Test func rejectsVersionWithEmbeddedWhitespace() {
        #expect(ClaudeCLIRelease.version(fromLatest: "2.1.251 extra words") == nil)
    }

    // MARK: - Manifest

    private static let checksum = String(repeating: "ab", count: 32)

    private func manifest(platform: String, checksum: String) -> Data {
        Data(
            """
            {"version": "2.1.251", "platforms": {"\(platform)": \
            {"checksum": "\(checksum)", "size": 123456}}}
            """.utf8)
    }

    @Test func readsChecksumForPlatform() {
        let data = manifest(platform: "darwin-arm64", checksum: Self.checksum)
        #expect(ClaudeCLIRelease.checksum(fromManifest: data, platform: "darwin-arm64") == Self.checksum)
    }

    @Test func missingPlatformYieldsNil() {
        let data = manifest(platform: "darwin-arm64", checksum: Self.checksum)
        #expect(ClaudeCLIRelease.checksum(fromManifest: data, platform: "darwin-x64") == nil)
    }

    @Test func malformedChecksumYieldsNil() {
        for bad in ["short", String(repeating: "AB", count: 32), String(repeating: "zz", count: 32)] {
            let data = manifest(platform: "darwin-arm64", checksum: bad)
            #expect(ClaudeCLIRelease.checksum(fromManifest: data, platform: "darwin-arm64") == nil)
        }
    }

    @Test func junkManifestYieldsNil() {
        #expect(ClaudeCLIRelease.checksum(fromManifest: Data("not json".utf8), platform: "darwin-arm64") == nil)
    }

    // MARK: - URLs

    @Test func urlsFollowTheReleaseLayout() {
        #expect(
            ClaudeCLIRelease.latestVersionURL.absoluteString
                == "https://downloads.claude.ai/claude-code-releases/latest"
        )
        #expect(
            ClaudeCLIRelease.manifestURL(version: "2.1.251").absoluteString
                == "https://downloads.claude.ai/claude-code-releases/2.1.251/manifest.json"
        )
        #expect(
            ClaudeCLIRelease.binaryURL(version: "2.1.251", platform: "darwin-arm64").absoluteString
                == "https://downloads.claude.ai/claude-code-releases/2.1.251/darwin-arm64/claude"
        )
    }

    @Test func platformKeys() {
        #expect(ClaudeCLIRelease.platform(isAppleSilicon: true) == "darwin-arm64")
        #expect(ClaudeCLIRelease.platform(isAppleSilicon: false) == "darwin-x64")
    }

    // MARK: - File checksum

    @Test func sha256MatchesKnownVector() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("checksum-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("abc".utf8).write(to: file)
        #expect(
            FileChecksum.sha256(of: file)
                == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    @Test func sha256OfEmptyFile() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("checksum-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data().write(to: file)
        #expect(
            FileChecksum.sha256(of: file)
                == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
    }

    @Test func sha256OfMissingFileYieldsNil() {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("checksum-test-\(UUID().uuidString)")
        #expect(FileChecksum.sha256(of: file) == nil)
    }
}
