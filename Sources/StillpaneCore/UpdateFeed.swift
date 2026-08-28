import Foundation

/// Parses the stillpane.dev/version.json feed and decides whether it
/// announces a newer version than the running one.
///
/// The endpoint is static JSON we author ourselves, but a half-deployed file,
/// a proxy error page, or a hijacked network must never produce a bogus
/// update banner - so the parse is strict and every failure means "no update".
public enum UpdateFeed {
    public struct Info: Equatable {
        public let version: String
        public let url: URL

        public init(version: String, url: URL) {
            self.version = version
            self.url = url
        }
    }

    /// The one destination an update notice may open: this repository's
    /// release page for exactly the announced version. A compromised feed can
    /// then at worst point at a real stillpane release, never at another
    /// host, another repository, or a non-release page.
    public static func parse(_ data: Data) -> Info? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let version = object["version"] as? String,
            isVersion(version),
            let urlString = object["url"] as? String,
            let url = URL(string: urlString),
            url.scheme == "https",
            url.host == "github.com",
            url.user == nil,
            url.password == nil,
            url.port == nil,
            url.query == nil,
            url.fragment == nil,
            url.path == "/yayamaz/stillpane/releases/tag/v\(version)"
        else { return nil }
        return Info(version: version, url: url)
    }

    /// Numeric dot-separated compare; missing components count as zero, so
    /// "1.0" and "1.0.0" are equal and "0.10.0" beats "0.9.9".
    public static func isNewer(_ remote: String, than local: String) -> Bool {
        let r = components(remote)
        let l = components(local)
        for i in 0..<max(r.count, l.count) {
            let a = i < r.count ? r[i] : 0
            let b = i < l.count ? l[i] : 0
            if a != b { return a > b }
        }
        return false
    }

    private static func isVersion(_ string: String) -> Bool {
        let parts = string.split(separator: ".", omittingEmptySubsequences: false)
        return !parts.isEmpty && parts.allSatisfy { UInt($0) != nil }
    }

    private static func components(_ string: String) -> [UInt] {
        string.split(separator: ".").compactMap { UInt($0) }
    }
}
