#if os(macOS)
import AppKit
import BrowserEngine
import Testing
import WebKit
@testable import WebKitEngine

@Suite(.serialized)
struct WebsiteDataStoreTests {
    @Test @MainActor func configuredPreviewModifierMatchesOnlyItsExactCombination() {
        let engine = WebKitEngine()
        engine.linkPreviewModifier = .option
        #expect(engine.shouldPreviewLink(on: [.option]))
        #expect(!engine.shouldPreviewLink(on: [.option, .command]))
        engine.linkPreviewModifier = .shift
        #expect(engine.shouldPreviewLink(on: [.shift]))
        #expect(!engine.shouldPreviewLink(on: [.shift, .control]))
        engine.linkPreviewModifier = .optionShift
        #expect(engine.shouldPreviewLink(on: [.option, .shift]))
        #expect(!engine.shouldPreviewLink(on: [.option, .shift, .command]))
        engine.linkPreviewModifier = .optionCommand
        #expect(engine.shouldPreviewLink(on: [.option, .command]))
        #expect(!engine.shouldPreviewLink(on: [.option]))
    }

    @Test @available(macOS 15.4, *) func recognizesOnlySecureChromeSignInRedirects() {
        let id = "kbfnbcaeplbcioakkpcpgfkobkghlhen"
        #expect(ExtensionAuth.redirectOwner(URL(string: "https://\(id).chromiumapp.org/?code=x")) == id)
        #expect(ExtensionAuth.redirectOwner(URL(string: "http://\(id).chromiumapp.org/")) == nil)
        #expect(ExtensionAuth.redirectOwner(URL(string: "https://not-an-id.chromiumapp.org/")) == nil)
        #expect(ExtensionAuth.isChromiumAppURL(URL(string: "https://\(id).chromiumapp.org/cb")))
        #expect(ExtensionAuth.isChromiumAppURL(URL(string: "https://chromiumapp.org/cb")))
        #expect(!ExtensionAuth.isChromiumAppURL(URL(string: "https://example.com/")))
    }

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
