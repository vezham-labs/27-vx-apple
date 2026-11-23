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
        try styles.set("main { display: none }", for: "elsewhere.test")
        let reopened = SiteStyles(fileURL: file)
        #expect(reopened["example.test"] == css)
        try reopened.set(" \n", for: "example.test")
        let cleaned = SiteStyles(fileURL: file)
        #expect(cleaned["example.test"] == nil)
        #expect(cleaned["elsewhere.test"] == "main { display: none }")
    }

    @Test @MainActor func extractsOnlyHTTPHostsWithoutMergingSubdomains() {
        #expect(SiteStyles.host(of: URL(string: "https://WWW.Example.test/path")) == "www.example.test")
        #expect(SiteStyles.host(of: URL(string: "http://example.test:8080")) == "example.test")
        #expect(SiteStyles.host(of: URL(string: "file:///tmp/local.html")) == nil)
        #expect(SiteStyles.host(of: URL(string: "data:text/html,hello")) == nil)
    }
}
