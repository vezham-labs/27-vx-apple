#if DEBUG
import Foundation
import BrowserCore
import WebKit

/// Launch arguments for the UI tests: a throwaway state file and a few local tabs, so tests never
/// touch your real tabs or the network. The arguments do nothing in release builds.
///
/// - `--ui-testing <tabs>`: start fresh with that many tabs.
/// - `--posture folded|unfolded`: pick the layout without a real fold.
/// - `--capture-fixture`: add a page element below the capture controls.
/// - `--site-style-fixture`: load synthetic markup with an HTTPS base URL.
/// - `--split-fixture`: use two synthetic web pages with distinct content.
/// - `--website-profile-fixture`: verify isolated profile stores without loading a website.
enum UITestSupport {
    static var forcedUnfolded: Bool? {
        guard let i = CommandLine.arguments.firstIndex(of: "--posture"), i + 1 < CommandLine.arguments.count else { return nil }
        return CommandLine.arguments[i + 1] == "unfolded"
    }

    @MainActor static func makeBrowser() -> BrowserState? {
        guard let i = CommandLine.arguments.firstIndex(of: "--ui-testing"), i + 1 < CommandLine.arguments.count,
              let count = Int(CommandLine.arguments[i + 1]) else { return nil }
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let browser = BrowserState(history: HistoryStore(fileURL: dir.appending(path: "history.json")),
                                   snapshotURL: dir.appending(path: "state.json"),
                                   thumbnailStore: nil)
        browser.settings.blockContent = false
        if CommandLine.arguments.contains("--website-profile-fixture") {
            let tab = browser.newTab(url: nil)
            Task { @MainActor in
                tab.customTitle = await verifyWebsiteProfiles(browser, tab: tab)
                    ? "Website profiles verified" : "Website profile verification failed"
            }
            return browser
        }
        if CommandLine.arguments.contains("--split-fixture") {
            for number in 1...2 {
                guard let url = URL(string: "https://split-fixture.test/pane-\(number)") else { continue }
                let tab = browser.newTab(url: nil)
                let session = browser.session(for: tab)
                tab.url = url
                tab.customTitle = "Pane \(number)"
                session.webView.loadHTMLString("""
                    <meta name="viewport" content="width=device-width">
                    <title>Pane \(number)</title>
                    <h1>Split page \(number)</h1>
                    """, baseURL: url)
            }
            return browser
        }
        if CommandLine.arguments.contains("--site-style-fixture"),
           let baseURL = URL(string: "https://site-style.test/") {
            let tab = browser.newTab(url: nil)
            browser.session(for: tab).webView.loadHTMLString("""
                <meta name="viewport" content="width=device-width">
                <title>Style Fixture</title>
                <h1 id="fixture-target">Style target</h1>
                """, baseURL: baseURL)
            return browser
        }
        let target = CommandLine.arguments.contains("--capture-fixture")
            ? "<p style='margin-top: 160px'>Capture target</p>" : ""
        for n in 1...max(count, 1) {
            let html = "<title>Tab \(n)</title><meta name=viewport content='width=device-width'><h1>Tab \(n)</h1>\(target)"
            _ = browser.newTab(url: URL(string: "data:text/html," + (html.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")))
        }
        return browser
    }

    @MainActor private static func verifyWebsiteProfiles(_ browser: BrowserState, tab: BrowserTab) async -> Bool {
        guard let profile = WebsiteProfile(name: "Fixture"),
              let second = browser.regularSpaces.first(where: { $0 !== browser.currentSpace }) else { return false }
        let first = browser.currentSpace
        browser.settings.websiteProfiles = [profile]
        let ordinaryTab = browser.newTab(url: nil, in: second)
        browser.select(tab)
        let previous = browser.session(for: tab)
        browser.assignWebsiteProfile(profile.id, to: first)
        let isolated = browser.session(for: tab)
        browser.assignWebsiteProfile(profile.id, to: second)
        let shared = browser.session(for: ordinaryTab)
        let passed = await checkCookies(isolated: isolated, shared: shared, defaultSession: previous, id: profile.id)
        browser.assignWebsiteProfile(nil, to: first)
        browser.assignWebsiteProfile(nil, to: second)
        let rebuilt = browser.session(for: tab)
        browser.settings.websiteProfiles = []
        return passed && isolated !== previous && rebuilt !== isolated
            && rebuilt.webView.configuration.websiteDataStore.identifier == nil
    }

    @MainActor private static func checkCookies(isolated: TabSession, shared: TabSession,
                                               defaultSession: TabSession, id: UUID) async -> Bool {
        let named = isolated.webView.configuration.websiteDataStore
        let same = shared.webView.configuration.websiteDataStore
        let standard = defaultSession.webView.configuration.websiteDataStore
        guard named.identifier == id, same.identifier == id, standard.identifier == nil,
              let cookie = HTTPCookie(properties: [
                .domain: "profile-fixture.invalid", .path: "/", .name: id.uuidString,
                .value: "isolated", .expires: Date.now.addingTimeInterval(600),
              ]) else { return false }
        await named.httpCookieStore.setCookie(cookie)
        let shares = await same.httpCookieStore.allCookies().contains { $0.name == cookie.name }
        let leaks = await standard.httpCookieStore.allCookies().contains { $0.name == cookie.name }
        await named.httpCookieStore.deleteCookie(cookie)
        return shares && !leaks
    }
}
#endif
