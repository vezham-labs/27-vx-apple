#if DEBUG
import Foundation
import BrowserCore

/// Launch arguments for the UI tests: a throwaway state file and a few local tabs, so tests never
/// touch your real tabs or the network. The arguments do nothing in release builds.
///
/// - `--ui-testing <tabs>`: start fresh with that many tabs.
/// - `--posture folded|unfolded`: pick the layout without a real fold.
/// - `--capture-fixture`: add a page element below the capture controls.
/// - `--site-style-fixture`: load synthetic markup with an HTTPS base URL.
/// - `--split-fixture`: use two synthetic web pages with distinct content.
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
        if CommandLine.arguments.contains("--split-fixture") {
            for number in 1...2 {
                guard let url = URL(string: "https://split-fixture.test/pane-\(number)") else { continue }
                let tab = browser.newTab(url: nil)
                let session = browser.session(for: tab)
                tab.url = url
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
}
#endif
