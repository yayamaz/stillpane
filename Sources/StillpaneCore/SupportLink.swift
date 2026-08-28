import Foundation

/// Builds the prefilled GitHub new-issue URL behind "Report a Problem".
public enum SupportLink {
    /// GitHub rejects URLs past ~8k characters; capping the body well short
    /// of that leaves room for the rest of the URL.
    static let bodyLimit = 6000

    /// A `+` in a query value reaches GitHub as a space under form decoding,
    /// so it is percent-encoded along with the query delimiters.
    private static let queryValueAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "+&=?")
        return set
    }()

    public static func newIssueURL(repoSlug: String, title: String, body: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "github.com"
        components.path = "/\(repoSlug)/issues/new"
        guard
            let encodedTitle = title.addingPercentEncoding(withAllowedCharacters: queryValueAllowed),
            let encodedBody = String(body.prefix(bodyLimit))
                .addingPercentEncoding(withAllowedCharacters: queryValueAllowed)
        else { return nil }
        components.percentEncodedQuery = "title=\(encodedTitle)&body=\(encodedBody)"
        return components.url
    }
}
