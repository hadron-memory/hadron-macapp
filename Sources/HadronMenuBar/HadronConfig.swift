import Foundation

/// Static configuration for talking to the Hadron platform.
///
/// Endpoints and the OAuth contract are documented in the platform specs
/// (`cor:api:010:01` for GraphQL, `cor:aut:030:01` for the OAuth 2.1 flow).
enum HadronConfig {
    /// The Hadron server that hosts the GraphQL + MCP transports and OAuth AS.
    static let baseURL = URL(string: "https://srv.hadronmemory.com")!

    /// GraphQL endpoint — the complete API surface.
    static var graphQLURL: URL { baseURL.appendingPathComponent("graphql") }

    /// RFC 8707 resource indicator. Required on `/oauth/authorize` and
    /// `/oauth/token`; it is the MCP resource the issued key is scoped to.
    static var resource: String { baseURL.appendingPathComponent("mcp").absoluteString }

    /// Only scope the AS advertises / accepts.
    static let scope = "mcp"

    /// Custom-scheme redirect. `ASWebAuthenticationSession` intercepts this
    /// internally, so no Info.plist URL-scheme registration is needed. The
    /// server's DCR validator accepts it because it parses to scheme +
    /// authority with no fragment (host = "oauth-callback").
    static let callbackScheme = "com.hadron.macapp"
    static let redirectURI = "com.hadron.macapp://oauth-callback"

    /// Human-readable client name recorded at dynamic registration.
    static let clientName = "Hadron for Mac"

    /// The web portal — used for "Open in portal" deep links.
    static let portalBaseURL = URL(string: "https://hadronmemory.com")!

    /// Build the shareable portal URL for a fully-qualified entity URN.
    /// e.g. `https://hadronmemory.com/app/u/hrn:node:org:memory:loc`
    static func portalURL(forURN urn: String) -> URL? {
        // Encode the URN as a single path segment — exclude "/" so a URN that
        // ever contains one doesn't split into extra segments.
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove("/")
        let encoded = urn.addingPercentEncoding(withAllowedCharacters: allowed) ?? urn
        return URL(string: "\(portalBaseURL.absoluteString)/app/u/\(encoded)")
    }
}
