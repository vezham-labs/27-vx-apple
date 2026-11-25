import Foundation

public enum URLNormalizer {
    /// "https://www.GitHub.com/foo/" -> "github.com/foo"
    public static func key(for url: URL) -> String {
        var host = (url.host() ?? "").lowercased()
        if host.hasPrefix("www.") { host.removeFirst(4) }
        var path = url.path()
        while path.hasSuffix("/") { path.removeLast() }
        var key = host + path
        if let q = url.query(), !q.isEmpty { key += "?" + q }
        return key
    }

    public static func displayHost(_ url: URL) -> String {
        var host = url.host() ?? url.absoluteString
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }

    /// Turns what the user typed into a URL if it plausibly is one, else nil (= search).
    public static func urlIfNavigable(_ raw: String) -> URL? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(" ") else { return nil }
        if let url = URL(string: text), let scheme = url.scheme?.lowercased(),
           ["http", "https", "about", "file", "ark"].contains(scheme) {
            return url
        }
        // "localhost:3000", "github.com", "192.168.1.1/admin"
        let hostPart = text.split(separator: "/", maxSplits: 1).first.map(String.init) ?? text
        let hostname = String(hostPart.split(separator: ":", maxSplits: 1).first ?? Substring(hostPart)).lowercased()
        let looksLikeHost = hostname.contains(".") || hostname == "localhost" || hostname.hasSuffix(".localhost")
        guard looksLikeHost, !hostPart.hasSuffix("."), !hostPart.hasPrefix(".") else { return nil }
        let local = hostname == "localhost" || hostname.hasSuffix(".localhost") || hostname.hasSuffix(".local")
            || hostname == "127.0.0.1" || hostname == "0.0.0.0" || Self.isPrivateIPv4(hostname)
        return URL(string: (local ? "http://" : "https://") + text)
    }

    private static func isPrivateIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        let octets = parts.compactMap { UInt8($0) }
        guard parts.count == 4, octets.count == 4 else { return false }
        return octets[0] == 10 || (octets[0] == 192 && octets[1] == 168)
            || (octets[0] == 172 && (16...31).contains(octets[1]))
    }
}

/// How well a typed query matches a candidate. Higher is better; 0 = no match.
public enum MatchQuality: Double, Comparable, Sendable {
    case none = 0
    case substring = 0.35
    case wordPrefix = 0.6
    case hostPrefix = 1.0

    public static func < (l: Self, r: Self) -> Bool { l.rawValue < r.rawValue }
}

public enum Matcher {
    /// Strips scheme and "www." so "git", "github", "https://github" all match "github.com".
    static func stripForMatching(_ s: String) -> String {
        var t = s.lowercased()
        for prefix in ["https://", "http://"] where t.hasPrefix(prefix) {
            t.removeFirst(prefix.count)
        }
        if t.hasPrefix("www.") { t.removeFirst(4) }
        return t
    }

    /// For things with no URL (commands): prefix of the title, any word, or any keyword.
    public static func titleQuality(query: String, title: String, keywords: [String] = []) -> MatchQuality {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return .none }
        let t = title.lowercased()
        if t.hasPrefix(q) { return .hostPrefix }
        let words = (t + " " + keywords.joined(separator: " ").lowercased())
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        let tokens = q.split(separator: " ")
        if tokens.allSatisfy({ tok in words.contains(where: { $0.hasPrefix(tok) }) }) { return .wordPrefix }
        return .none
    }

    public static func quality(query: String, url: URL, title: String) -> MatchQuality {
        let q = stripForMatching(query.trimmingCharacters(in: .whitespaces))
        guard !q.isEmpty else { return .none }
        let key = URLNormalizer.key(for: url)
        if key.hasPrefix(q) { return .hostPrefix }

        let lowerTitle = title.lowercased()
        let words = (lowerTitle + " " + key)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        // Multi-word queries: every query token must prefix some word.
        let tokens = q.split(separator: " ")
        if tokens.allSatisfy({ tok in words.contains(where: { $0.hasPrefix(tok) }) }) {
            return .wordPrefix
        }
        if key.contains(q) || lowerTitle.contains(q) { return .substring }
        return .none
    }
}
