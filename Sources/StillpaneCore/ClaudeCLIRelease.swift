import CryptoKit
import Foundation

/// The layout of Claude Code's release feed, and validation for what it
/// serves.
///
/// The feed is three fetches: `latest` (a bare version string), a manifest
/// naming a SHA-256 per platform, and the binary itself. The app's installer
/// does the downloading; this type owns the URLs and the parsing so both stay
/// testable, and so a served error page can never be mistaken for a version
/// or a checksum.
public enum ClaudeCLIRelease {
    private static let base = "https://downloads.claude.ai/claude-code-releases"

    public static var latestVersionURL: URL {
        URL(string: "\(base)/latest")!
    }

    public static func manifestURL(version: String) -> URL {
        URL(string: "\(base)/\(version)/manifest.json")!
    }

    public static func binaryURL(version: String, platform: String) -> URL {
        URL(string: "\(base)/\(version)/\(platform)/claude")!
    }

    public static func platform(isAppleSilicon: Bool) -> String {
        isAppleSilicon ? "darwin-arm64" : "darwin-x64"
    }

    /// The version the `latest` endpoint answered, or nil when the response
    /// is not one (an error page, an empty body). The version is interpolated
    /// into the follow-up URLs, so nothing but a version token may pass.
    public static func version(fromLatest raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^[0-9]+\.[0-9]+\.[0-9]+[0-9A-Za-z.+-]*$"#
        guard trimmed.range(of: pattern, options: .regularExpression) != nil else { return nil }
        return trimmed
    }

    private struct Manifest: Decodable {
        struct Platform: Decodable {
            let checksum: String
        }
        let platforms: [String: Platform]
    }

    /// The manifest's SHA-256 for one platform, or nil when the manifest does
    /// not parse, does not know the platform, or carries anything that is not
    /// a lowercase 64-hex digest.
    public static func checksum(fromManifest data: Data, platform: String) -> String? {
        guard let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
            let checksum = manifest.platforms[platform]?.checksum,
            checksum.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil
        else { return nil }
        return checksum
    }
}

/// SHA-256 of a file on disk, streamed so a large binary never has to fit in
/// memory.
public enum FileChecksum {
    public static func sha256(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
