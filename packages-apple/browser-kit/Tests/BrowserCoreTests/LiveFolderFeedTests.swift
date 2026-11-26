import Foundation
import Testing
@testable import BrowserCore

struct LiveFolderFeedTests {
    private let source = URL(string: "https://example.com/feeds/latest.xml")!

    @MainActor @Test func githubRefreshPreservesChangesAndDoesNotRecreateDeletedFolder() async throws {
        let space = Space(name: "Work")
        let folder = try #require(space.addPinFolder(named: "Pull Requests"))
        let feed = LiveFolderFeed(source: try #require(URL(string: "https://github.com/_ark/live-pull-requests")), title: "Pull Requests", articles: [
            .init(title: "Review", url: try #require(URL(string: "https://github.com/acme/app/pull/1")))
        ])
        space.pinFolders[0].feed = feed
        var firstStarted = false
        let refresh = Task { @MainActor in
            try await space.refreshGitHubPullRequests {
                firstStarted = true
                try await Task.sleep(for: .milliseconds(100))
                return feed
            }
        }
        await Task.yield()
        #expect(firstStarted)
        space.setGitHubOwner("acme", shown: false, in: folder.id)
        _ = try await refresh.value
        #expect(space.pinFolders[0].visibleArticles.isEmpty)
        var secondStarted = false
        let deletedRefresh = Task { @MainActor in
            try await space.refreshGitHubPullRequests {
                secondStarted = true
                try await Task.sleep(for: .milliseconds(100))
                return feed
            }
        }
        await Task.yield()
        #expect(secondStarted)
        space.removePinFolder(folder.id)
        #expect(try await deletedRefresh.value == nil)
        #expect(space.pinFolders.isEmpty)
        let newFolder = try #require(space.addPinFolder(named: "Pull Requests"))
        space.pinFolders[0].feed = feed
        let changedFeed = LiveFolderFeed(source: feed.source, title: feed.title, articles: [])
        var thirdStarted = false
        let profileRefresh = Task { @MainActor in
            try await space.refreshGitHubPullRequests {
                thirdStarted = true
                try await Task.sleep(for: .milliseconds(100))
                return changedFeed
            }
        }
        await Task.yield()
        #expect(thirdStarted)
        space.websiteProfileID = UUID()
        #expect(try await profileRefresh.value == nil)
        #expect(space.pinFolders.first { $0.id == newFolder.id }?.feed == feed)
    }

    @MainActor @Test func githubOwnerFiltersAreLocalReversibleAndPersisted() throws {
        let work = Space(name: "Work")
        let personal = Space(name: "Personal")
        let workFolder = try #require(work.addPinFolder(named: "Pull Requests"))
        _ = try #require(personal.addPinFolder(named: "Pull Requests"))
        let feed = LiveFolderFeed(source: try #require(URL(string: "https://github.com/_ark/live-pull-requests")), title: "Pull Requests", articles: [
            .init(title: "Work", url: try #require(URL(string: "https://github.com/Acme/app/pull/1"))),
            .init(title: "Personal", url: try #require(URL(string: "https://github.com/me/app/pull/2"))),
        ])
        work.pinFolders[0].feed = feed
        personal.pinFolders[0].feed = feed
        #expect(work.pinFolders[0].githubOwners == ["acme", "me"])
        work.setGitHubOwner("ACME", shown: false, in: workFolder.id)
        #expect(work.pinFolders[0].visibleArticles.map(\.title) == ["Personal"])
        #expect(work.pinFolders[0].feed?.articles.count == 2)
        #expect(personal.pinFolders[0].visibleArticles.count == 2)
        let archive = try #require(SpaceLinkArchive(space: work))
        let shared = String(decoding: try archive.encoded(), as: UTF8.self)
        #expect(!shared.contains("acme"))
        #expect(!shared.contains("knownGitHubOwners"))
        #expect(!shared.contains("hiddenGitHubOwners"))
        let restored = Space(try JSONDecoder().decode(SpaceRecord.self, from: JSONEncoder().encode(work.record)))
        #expect(restored.pinFolders[0].visibleArticles.map(\.title) == ["Personal"])
        restored.pinFolders[0].feed = LiveFolderFeed(source: feed.source, title: feed.title, articles: [feed.articles[1]])
        #expect(restored.pinFolders[0].githubOwners == ["acme", "me"])
        restored.setGitHubOwner("acme", shown: true, in: workFolder.id)
        restored.pinFolders[0].feed = feed
        #expect(restored.pinFolders[0].visibleArticles.count == 2)
    }

    @MainActor @Test func githubOwnerFilteringDoesNotTreatOtherHostsAsOrganizations() throws {
        let space = Space(name: "Work")
        let folder = try #require(space.addPinFolder(named: "Pull Requests"))
        let source = try #require(URL(string: "https://github.com/_ark/live-pull-requests"))
        let articles = [
            LiveFolderFeed.Article(title: "GitHub", url: try #require(URL(string: "https://github.com/acme/app/pull/1"))),
            LiveFolderFeed.Article(title: "Other host", url: try #require(URL(string: "https://evilgithub.com/acme/app/pull/2"))),
            LiveFolderFeed.Article(title: "Not a pull", url: try #require(URL(string: "https://github.com/acme/app/issues/3"))),
        ]
        space.pinFolders[0].feed = LiveFolderFeed(source: source, title: folder.name, articles: articles)
        space.setGitHubOwner("acme", shown: false, in: folder.id)
        #expect(space.pinFolders[0].githubOwners == ["acme"])
        #expect(space.pinFolders[0].visibleArticles.map(\.title) == ["Other host", "Not a pull"])
    }

    @Test func githubCredentialsStayOnTheExpectedOrigin() throws {
        for value in ["https://github.com/pulls", "https://GITHUB.COM:443/login"] {
            #expect(GitHubRedirectGuard.isAllowed(try #require(URL(string: value))))
        }
        for value in ["http://github.com/pulls", "https://github.com:444/pulls", "https://evilgithub.com/", "https://github.com.evil.test/", "https://user:pass@github.com/"] {
            #expect(!GitHubRedirectGuard.isAllowed(try #require(URL(string: value))))
        }
        func cookie(_ domain: String, _ path: String) throws -> HTTPCookie {
            try #require(HTTPCookie(properties: [.domain: domain, .path: path, .name: "session", .value: "fixture"]))
        }
        #expect(GitHubRedirectGuard.isSafeCookie(try cookie(".github.com", "/")))
        #expect(!GitHubRedirectGuard.isSafeCookie(try cookie("gist.github.com", "/")))
        #expect(!GitHubRedirectGuard.isSafeCookie(try cookie("github.com", "/other")))
    }

    @Test func githubRedirectDelegateBlocksOtherOrigins() async throws {
        let source = try #require(URL(string: "https://github.com/pulls"))
        let response = try #require(HTTPURLResponse(url: source, statusCode: 302, httpVersion: nil, headerFields: nil))
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: source)
        let guardDelegate = GitHubRedirectGuard()
        func redirect(_ target: String) async throws -> URLRequest? {
            let request = URLRequest(url: try #require(URL(string: target)))
            return await withCheckedContinuation { continuation in
                guardDelegate.urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: request) {
                    continuation.resume(returning: $0)
                }
            }
        }
        #expect(try await redirect("https://github.com/login") != nil)
        #expect(try await redirect("https://attacker.test/") == nil)
        #expect(try await redirect("http://github.com/") == nil)
    }

    @MainActor @Test func scheduledGitHubRefreshSkipsPausedAndRemovedFolders() async throws {
        let space = Space(name: "Work")
        let folder = try #require(space.addPinFolder(named: "Pull Requests"))
        let source = try #require(URL(string: "https://github.com/_ark/live-pull-requests"))
        space.pinFolders[0].feed = LiveFolderFeed(source: source, title: folder.name, articles: [])
        #expect(space.automaticGitHubFolderID == folder.id)

        space.pinFolders[0].feedNeedsActivation = true
        #expect(space.automaticGitHubFolderID == nil)
        let paused = try await space.refreshGitHubPullRequests(cookies: [], existingFolderID: folder.id)
        #expect(paused == nil)
        #expect(space.pinFolders.first?.feedNeedsActivation == true)

        space.removePinFolder(folder.id)
        let removed = try await space.refreshGitHubPullRequests(cookies: [], existingFolderID: folder.id)
        #expect(removed == nil)
        #expect(space.pinFolders.isEmpty)
    }

    @Test func rssResolvesRelativeLinksAndFiltersDuplicates() throws {
        let xml = """
            <rss version="2.0"><channel><title>  Research   notes </title>
              <item><title>First &amp; latest</title><link>../first</link></item>
              <item><title>Duplicate</title><link>https://example.com/first</link></item>
              <item><guid isPermaLink="false">https://example.com/unlinked</guid></item>
              <item><guid>https://example.com/second</guid></item>
              <item><link>file:///private/local</link></item>
            </channel></rss>
            """
        let feed = try #require(LiveFolderFeed.parse(Data(xml.utf8), source: source))
        #expect(feed.title == "Research notes")
        #expect(feed.articles.map(\.url.absoluteString) == ["https://example.com/first", "https://example.com/second"])
        #expect(feed.articles.first?.title == "First & latest")
    }

    @Test func atomUsesAlternateLinksAndKeepsStableIdentity() throws {
        let xml = """
            <feed xmlns="http://www.w3.org/2005/Atom" xml:base="/articles/">
              <title>Field notes</title>
              <entry><title type="html">&lt;em&gt;First&lt;/em&gt; article</title>
                <link rel="enclosure" href="clip.mp4"/><link href="atlas"/>
                <source><title>Original publication</title></source>
              </entry>
            </feed>
            """
        let feed = try #require(LiveFolderFeed.parse(Data(xml.utf8), source: source))
        let changed = xml.replacingOccurrences(of: "First", with: "Updated")
        let updated = try #require(LiveFolderFeed.parse(Data(changed.utf8), source: source))
        #expect(feed.articles.first?.title == "First article")
        #expect(feed.articles.first?.id.absoluteString == "https://example.com/articles/atlas")
        #expect(updated.articles.first?.id == feed.articles.first?.id)
    }

    @Test func siteDiscoveryAndParserLimits() throws {
        let html = """
            <html><head>
            <!-- <link rel="alternate" type="application/rss+xml" href="/comment"> -->
            <script>let asset = '<link rel="alternate" type="application/rss+xml" href="/script">';</script>
            <link rel='alternate' type='application/atom+xml' href='../atom?edition=1&amp;lang=en'>
            </head></html>
            """
        #expect(LiveFolderFeed.discover(Data(html.utf8), page: source)?.absoluteString == "https://example.com/atom?edition=1&lang=en")
        let entries = (0..<60).map { "<item><link>/item/\($0)</link></item>" }.joined()
        let xml = "<rss><channel>\(entries)</channel></rss>"
        let feed = try #require(LiveFolderFeed.parse(Data(xml.utf8), source: source))
        #expect(feed.articles.count == LiveFolderFeed.articleLimit)
        #expect(LiveFolderFeed.parse(Data("<rss><channel></rss>".utf8), source: source) == nil)
        #expect(LiveFolderFeed.parse(Data(repeating: 0, count: LiveFolderFeed.byteLimit + 1), source: source) == nil)
    }

    @MainActor @Test func liveFeedSurvivesSpaceSnapshotAndOldFoldersDecode() throws {
        let space = Space(name: "Work")
        let id = try #require(space.addPinFolder(named: "Reading")).id
        let xml = "<rss><channel><item><link>/atlas</link></item></channel></rss>"
        space.pinFolders[0].feed = try #require(LiveFolderFeed.parse(Data(xml.utf8), source: source))
        let data = try JSONEncoder().encode(space.record)
        let restored = Space(try JSONDecoder().decode(SpaceRecord.self, from: data))
        #expect(restored.pinFolders.first?.feed == space.pinFolders.first?.feed)

        let old = """
            {"id":"\(id)","name":"Reading","isCollapsed":false}
            """
        #expect(try JSONDecoder().decode(PinFolder.self, from: Data(old.utf8)).feed == nil)
    }
}
