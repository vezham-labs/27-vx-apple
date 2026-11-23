import Foundation
import Testing
@testable import BrowserCore

struct LiveFolderFeedTests {
    private let source = URL(string: "https://example.com/feeds/latest.xml")!

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
