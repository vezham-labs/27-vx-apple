import Foundation

public struct LiveFolderFeed: Codable, Equatable, Sendable {
    public struct Article: Codable, Equatable, Identifiable, Sendable {
        public var id: URL { url }
        public let title: String
        public let url: URL
    }

    public let source: URL
    public let title: String
    public let articles: [Article]

    public init(source: URL, title: String, articles: [Article]) {
        self.source = source
        self.title = title
        self.articles = articles
    }

    static let byteLimit = 2_000_000
    static let articleLimit = 30
    private static let gitHubPullsSource = URL(string: "https://github.com/_ark/live-pull-requests")!

    /// True for Ark's signed-in GitHub Pull Requests folder rather than an RSS/Atom feed.
    public var isGitHubPullRequests: Bool { source == Self.gitHubPullsSource }

    enum LoadError: LocalizedError {
        case invalidAddress, requestFailed, tooLarge, missingFeed

        var errorDescription: String? {
            switch self {
            case .invalidAddress: "Enter an HTTP or HTTPS feed or website address."
            case .requestFailed: "Ark couldn’t reach the feed."
            case .tooLarge: "The response is too large for a live folder."
            case .missingFeed: "Ark couldn’t find a readable RSS or Atom feed."
            }
        }
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.httpAdditionalHeaders = ["Accept": "application/rss+xml, application/atom+xml, application/xml, text/xml, text/html;q=0.5"]
        return URLSession(configuration: config)
    }()

    static func load(address: String) async throws -> LiveFolderFeed {
        let address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let urlString = address.contains("://") ? address : "https://" + address
        guard !address.contains(where: \.isWhitespace), let url = webURL(urlString) else { throw LoadError.invalidAddress }
        let (data, finalURL) = try await fetch(url)
        if let feed = parse(data, source: finalURL) { return feed }
        if let found = discover(data, page: finalURL), found != finalURL {
            let (feedData, feedURL) = try await fetch(found)
            if let feed = parse(feedData, source: feedURL) { return feed }
        }
        throw LoadError.missingFeed
    }

    /// Reads GitHub's Pull Requests page with the Space's existing GitHub cookies. Cookies are
    /// supplied by the engine, stay in memory, and are sent only to github.com.
    public static func loadGitHubPullRequests(cookies: [HTTPCookie]) async throws -> LiveFolderFeed {
        var components = URLComponents(string: "https://github.com/pulls")!
        components.queryItems = [URLQueryItem(name: "q", value: "is:pr is:open archived:false involves:@me sort:updated-desc")]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 15
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("Ark", forHTTPHeaderField: "User-Agent")
        let matching = cookies.filter { cookie in
            let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return domain == "github.com" || domain.hasSuffix(".github.com")
        }
        let headers = HTTPCookie.requestHeaderFields(with: matching)
        for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        let (data, response) = try await URLSession(configuration: configuration).data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw LoadError.requestFailed
        }
        let finalPath = http.url?.path ?? ""
        let body = String(decoding: data, as: UTF8.self)
        if finalPath == "/login" || body.contains("name=\"user-login\" content=\"\"") {
            throw LoadError.requestFailed
        }
        return LiveFolderFeed(source: gitHubPullsSource, title: "Pull Requests", articles: GitHubPullReader.articles(from: body))
    }

    private static func fetch(_ url: URL) async throws -> (Data, URL) {
        let (bytes, response) = try await session.bytes(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let address = http.url?.absoluteString, let finalURL = webURL(address) else {
            throw LoadError.requestFailed
        }
        guard response.expectedContentLength <= byteLimit else { throw LoadError.tooLarge }
        var data = Data()
        for try await byte in bytes {
            guard data.count < byteLimit else { throw LoadError.tooLarge }
            data.append(byte)
        }
        return (data, finalURL)
    }

    static func webURL(_ text: String, relativeTo base: URL? = nil) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed, relativeTo: base)?.absoluteURL,
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              url.host()?.isEmpty == false, url.user == nil, url.password == nil else { return nil }
        return url
    }

    static func discover(_ data: Data, page: URL) -> URL? {
        guard data.count <= byteLimit,
              let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return nil }
        let candidates = #/<!--(?s:.*?)-->|<(?:script|style)\b[^>]*>(?s:.*?)<\/(?:script|style)\s*>|<\/?(?:head|body)\b[^>]*>|<link\b(?:[^>"']|"[^"]*"|'[^']*')*>/#.ignoresCase()
        let attributePattern = #/([\w:-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/#
        for match in html.matches(of: candidates) {
            let tag = match.output
            let start = tag.prefix(7).lowercased()
            if start.hasPrefix("</head") || start.hasPrefix("<body") { break }
            guard start.hasPrefix("<link") else { continue }
            let attributes = Dictionary(tag.matches(of: attributePattern).map { attribute in
                (String(attribute.output.1).lowercased(), String(attribute.output.2 ?? attribute.output.3 ?? attribute.output.4 ?? ""))
            }, uniquingKeysWith: { first, _ in first })
            guard attributes["rel"]?.lowercased().split(whereSeparator: \.isWhitespace).contains("alternate") == true,
                  let type = attributes["type"]?.lowercased().split(separator: ";").first,
                  ["application/rss+xml", "application/atom+xml"].contains(String(type)),
                  let href = attributes["href"],
                  let url = webURL(href.replacingOccurrences(of: "&amp;", with: "&"), relativeTo: page) else { continue }
            return url
        }
        return nil
    }

    static func parse(_ data: Data, source: URL) -> LiveFolderFeed? {
        guard data.count <= byteLimit else { return nil }
        let reader = FeedReader(source: source)
        let parser = XMLParser(data: data)
        parser.externalEntityResolvingPolicy = .never
        parser.delegate = reader
        guard parser.parse(), reader.recognized else { return nil }
        return LiveFolderFeed(source: source, title: reader.title ?? source.host() ?? "Live Folder", articles: reader.articles)
    }
}

private enum GitHubPullReader {
    static func articles(from html: String) -> [LiveFolderFeed.Article] {
        let pattern = #"<a\b([^>]*\bhref=[\"'](/[^\"'#?\s]+/[^\"'#?\s]+/pull/(\d+))[^>]*)(?:>([\s\S]*?)</a>)"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let text = html as NSString
        var seen = Set<URL>()
        return expression.matches(in: html, range: NSRange(location: 0, length: text.length)).compactMap { match in
            guard match.numberOfRanges >= 5 else { return nil }
            let path = text.substring(with: match.range(at: 2))
            let inner = text.substring(with: match.range(at: 4))
            guard let url = URL(string: "https://github.com" + path), seen.insert(url).inserted else { return nil }
            let title = inner.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&quot;", with: "\"")
                .split(whereSeparator: \.isWhitespace).joined(separator: " ")
            let label = title.isEmpty ? path.split(separator: "/").dropLast().joined(separator: "/") + " #" + text.substring(with: match.range(at: 3)) : title
            return LiveFolderFeed.Article(title: label, url: url)
        }.prefix(LiveFolderFeed.articleLimit).map { $0 }
    }
}

private final class FeedReader: NSObject, XMLParserDelegate {
    private enum Field { case feedTitle, articleTitle, link, guid }

    private struct Entry {
        let depth: Int
        var title: String?
        var link: URL?
        var guid: URL?
    }

    private struct Capture {
        let field: Field
        let depth: Int
        let base: URL
        let containsHTML: Bool
        var text = ""
    }

    private let source: URL
    private var path: [String] = []
    private var bases: [URL] = []
    private var entry: Entry?
    private var capture: Capture?
    private var seen: Set<URL> = []
    private(set) var recognized = false
    private(set) var title: String?
    private(set) var articles: [LiveFolderFeed.Article] = []

    init(source: URL) { self.source = source }

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String]) {
        guard path.count < 64 else { parser.abortParsing(); return }
        let name = element.split(separator: ":").last?.lowercased() ?? element.lowercased()
        let base = bases.last ?? source
        bases.append(attributes["xml:base"].flatMap { LiveFolderFeed.webURL($0, relativeTo: base) } ?? base)
        path.append(name)
        if path.count == 1 { recognized = ["rss", "feed", "rdf"].contains(name) }
        guard recognized, capture == nil else { return }

        if path == ["rss", "channel", "item"] || path == ["rdf", "item"] || path == ["feed", "entry"] {
            if articles.count < LiveFolderFeed.articleLimit { entry = Entry(depth: path.count) }
        } else if path == ["feed", "title"] || path == ["rss", "channel", "title"] || path == ["rdf", "channel", "title"] {
            begin(.feedTitle, html: attributes["type"] == "html")
        } else if let entry, path.count == entry.depth + 1 {
            switch name {
            case "title":
                begin(.articleTitle, html: attributes["type"] == "html")
            case "link" where entry.link == nil:
                if let href = attributes["href"] {
                    if (attributes["rel"] ?? "alternate").lowercased() == "alternate" {
                        self.entry?.link = LiveFolderFeed.webURL(href, relativeTo: bases.last)
                    }
                } else {
                    begin(.link)
                }
            case "guid" where path.first == "rss" && attributes["isPermaLink"]?.lowercased() != "false":
                begin(.guid)
            default: break
            }
        }
    }

    private func begin(_ field: Field, html: Bool = false) {
        capture = Capture(field: field, depth: path.count, base: bases.last ?? source, containsHTML: html)
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if let count = capture?.text.utf8.count, count < 8_192 { capture?.text.append(contentsOf: string.prefix(8_192 - count)) }
    }

    func parser(_ parser: XMLParser, foundCDATA bytes: Data) {
        if let string = String(data: bytes, encoding: .utf8) { self.parser(parser, foundCharacters: string) }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        defer { path.removeLast(); bases.removeLast() }
        if let capture, capture.depth == path.count {
            self.capture = nil
            switch capture.field {
            case .feedTitle: title = displayTitle(capture)
            case .articleTitle: entry?.title = displayTitle(capture)
            case .link: entry?.link = LiveFolderFeed.webURL(capture.text, relativeTo: capture.base)
            case .guid: entry?.guid = LiveFolderFeed.webURL(capture.text)
            }
        }
        if let entry, entry.depth == path.count {
            self.entry = nil
            if let url = entry.link ?? entry.guid, seen.insert(url).inserted {
                articles.append(.init(title: entry.title ?? url.host() ?? url.absoluteString, url: url))
            }
        }
    }

    private func displayTitle(_ capture: Capture) -> String? {
        let plain = capture.containsHTML ? capture.text.replacing(#/<[^>]*>/#, with: "") : capture.text
        let text = plain.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return text.isEmpty ? nil : String(text.prefix(240))
    }
}
