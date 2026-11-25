import Foundation
import Testing
import WebKit
@testable import BrowserCore

struct SiteStylesTests {
    @Test @MainActor func classSelectionStaysSingularWhenPageAddsMatches() async throws {
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 600, height: 400))
        let navigation = NavigationWaiter()
        webView.navigationDelegate = navigation
        webView.loadHTMLString("<body><article class='card'>Original</article></body>", baseURL: URL(string: "https://example.test/"))
        try await navigation.finished()
        let selection = try #require(await PageCaptureImage.selection(at: CGPoint(x: 15, y: 15), in: webView))
        #expect(selection.selector == "article.card")
        let fingerprint = try #require(selection.fingerprint)
        let styles = SiteStyles(fileURL: nil)
        try styles.hide(HiddenSiteElement(selector: selection.selector, label: selection.label,
                                          fingerprint: fingerprint, family: selection.family), for: "example.test")
        await styles.apply(to: webView, on: "example.test")
        _ = try await webView.evaluateJavaScript("document.body.insertAdjacentHTML('beforeend', '<article class=card>Other</article>')")
        try await Task.sleep(for: .milliseconds(100))
        let hidden = try await webView.evaluateJavaScript("Array.from(document.querySelectorAll('article')).map(e => getComputedStyle(e).display).join(',')") as? String
        #expect(hidden == "none,block")
        _ = try await webView.evaluateJavaScript("document.querySelectorAll('article')[1].textContent = 'Original'")
        try await Task.sleep(for: .milliseconds(100))
        let ambiguous = try await webView.evaluateJavaScript("Array.from(document.querySelectorAll('article')).map(e => getComputedStyle(e).display).join(',')") as? String
        #expect(ambiguous == "block,block")
    }
    @Test @MainActor func savesAndRemovesStylesWithoutChangingOtherHosts() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "site-styles.json")
        let styles = SiteStyles(fileURL: file)
        let css = "h1 { color: rebeccapurple }"
        try styles.set(css, for: "example.test")
        try styles.setFont(.serif, for: "example.test")
        try styles.set("main { display: none }", for: "elsewhere.test")
        let reopened = SiteStyles(fileURL: file)
        #expect(reopened["example.test"] == css)
        #expect(reopened.font(for: "example.test") == .serif)
        #expect(reopened.font(for: "elsewhere.test") == .original)
        try reopened.set(" \n", for: "example.test")
        let cleaned = SiteStyles(fileURL: file)
        #expect(cleaned["example.test"] == nil)
        #expect(cleaned["elsewhere.test"] == "main { display: none }")
        #expect(cleaned.font(for: "example.test") == .serif)
    }

    @Test @MainActor func extractsOnlyHTTPHostsWithoutMergingSubdomains() {
        #expect(SiteStyles.host(of: URL(string: "https://WWW.Example.test/path")) == "www.example.test")
        #expect(SiteStyles.host(of: URL(string: "http://example.test:8080")) == "example.test")
        #expect(SiteStyles.host(of: URL(string: "file:///tmp/local.html")) == nil)
        #expect(SiteStyles.host(of: URL(string: "data:text/html,hello")) == nil)
    }

    @Test @MainActor func persistsGuardedHiddenElementsAndKeepsTheirMarkerStable() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "site-styles.json")
        let element = HiddenSiteElement(selector: "main > article:nth-of-type(2)", label: "Plan",
                                        fingerprint: "article\\n\\nPlan a dinner", family: "article.card")
        let styles = SiteStyles(fileURL: file)
        try styles.hide(element, for: "example.test")
        let reopened = SiteStyles(fileURL: file)
        #expect(reopened.hiddenElements(for: "example.test") == [element])
        #expect(reopened.hiddenElements(for: "example.test").first?.guardKey == element.guardKey)
    }
}

@MainActor private final class NavigationWaiter: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, any Error>?
    private var result: Result<Void, any Error>?

    func finished() async throws {
        if let result { return try result.get() }
        try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { complete(.success(())) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) { complete(.failure(error)) }

    private func complete(_ result: Result<Void, any Error>) {
        self.result = result
        continuation?.resume(with: result)
        continuation = nil
    }
}
