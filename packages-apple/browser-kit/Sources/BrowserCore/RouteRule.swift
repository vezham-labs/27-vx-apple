import Foundation

public struct RouteRule: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    /// "github.com" (and its subdomains), optionally with a path: "github.com/acme".
    public var pattern: String
    public var spaceID: UUID

    public init(pattern: String, spaceID: UUID) {
        self.pattern = pattern
        self.spaceID = spaceID
    }

    public var host: String { Self.host(of: pattern) }
    public var pathPrefix: String? { Self.pathPrefix(of: pattern) }

    public func matches(_ url: URL) -> Bool { Self.pattern(pattern, matches: url) }

    /// More specific rules (with a path, longer host) win.
    public var specificity: Int { Self.specificity(of: pattern) }

    public static func host(of pattern: String) -> String { String(pattern.split(separator: "/", maxSplits: 1).first ?? "") }

    public static func pathPrefix(of pattern: String) -> String? {
        let parts = pattern.split(separator: "/", maxSplits: 1)
        return parts.count == 2 ? "/" + parts[1] : nil
    }

    public static func specificity(of pattern: String) -> Int { pattern.count + (pathPrefix(of: pattern) == nil ? 0 : 1000) }

    public static func pattern(_ pattern: String, matches url: URL) -> Bool {
        guard let h = url.host()?.lowercased() else { return false }
        let bare = h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
        let host = host(of: pattern)
        guard bare == host || bare.hasSuffix("." + host) else { return false }
        guard let prefix = pathPrefix(of: pattern) else { return true }
        let path = url.path().lowercased()
        return path == prefix || path.hasPrefix(prefix.hasSuffix("/") ? prefix : prefix + "/")
    }

    /// "github.com/acme/web" from a page's address, for a rule that covers just that path.
    public static func pattern(for url: URL, depth: Int) -> String? {
        guard let h = url.host()?.lowercased() else { return nil }
        let host = h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
        let segments = url.pathComponents.dropFirst().prefix(depth).map { $0.lowercased() }
        return ([host] + segments).joined(separator: "/")
    }

    public static func normalizedPattern(_ input: String) -> String? {
        let input = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = input.contains("://") ? input : "https://" + input
        guard let url = URL(string: address), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.user == nil, url.password == nil, url.port == nil,
              url.query == nil, url.fragment == nil, let host = url.host()?.lowercased(),
              host == "localhost" || (host.contains(".") && !host.contains(":")),
              host.split(separator: ".", omittingEmptySubsequences: false).allSatisfy({ label in
                  !label.isEmpty && label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
              }) else { return nil }
        let canonicalHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        let path = url.path().trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        return path.isEmpty ? canonicalHost : canonicalHost + "/" + path
    }

    public static func bestMatch(for url: URL, rules: [Self], destinations: Set<UUID>) -> Self? {
        guard !rules.isEmpty, allowsRouting(url) else { return nil }
        return rules.lazy.filter { destinations.contains($0.spaceID) && $0.matches(url) }
            .max { $0.specificity < $1.specificity }
    }

    public static func allowsRouting(_ url: URL) -> Bool {
        guard url.scheme == "http" || url.scheme == "https" else { return false }
        return !neverRouted.contains { pattern($0, matches: url) }
    }

    /// Sign-ins and checkouts open next to the tab that asked for them, or the flow breaks.
    private static let neverRouted: [String] = [
        "accounts.google.com", "login.microsoftonline.com", "login.live.com", "appleid.apple.com", "idmsa.apple.com",
        "okta.com", "auth0.com", "onelogin.com", "github.com/login", "github.com/sessions", "slack.com/signin",
        "checkout.stripe.com", "paypal.com", "pay.google.com",
    ]
}
