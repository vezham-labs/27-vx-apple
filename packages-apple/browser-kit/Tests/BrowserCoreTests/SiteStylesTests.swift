import Foundation
import Testing
@testable import BrowserCore

struct SiteStylesTests {
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
