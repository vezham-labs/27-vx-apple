#if os(macOS)
import AppKit
import BrowserEngine
import Testing
import WebKit
import WebKitEngine

@Suite(.serialized)
struct WebsiteDataStoreTests {
    @Test @MainActor func deletingNamedProfileStoreRemovesItsPersistentCookies() async throws {
        let id = UUID()
        let engine = WebKitEngine()
        let cookie = try #require(HTTPCookie(properties: [
            .domain: "example.com", .path: "/", .name: "ark-delete-\(id.uuidString)",
            .value: "fixture", .expires: Date.now.addingTimeInterval(600),
        ]))
        func createPageAndWriteCookie() async throws {
            let page = engine.makePage(options: PageOptions(profile: .named(id)), delegate: TestPageDelegate())
            let webView = try #require(page.view as? WKWebView)
            await webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie)
            page.close()
        }
        try await createPageAndWriteCookie()

        await engine.deleteWebsiteDataStore(for: .named(id))
        let recreated = WKWebsiteDataStore(forIdentifier: id)
        let retainedCookie = await recreated.httpCookieStore.allCookies().contains { $0.name == cookie.name }
        #expect(!retainedCookie)
        try? await WKWebsiteDataStore.remove(forIdentifier: id)
    }
}

private final class TestPageDelegate: EnginePageDelegate {}
#endif
