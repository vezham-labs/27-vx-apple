#if os(iOS)
import Foundation

extension BrowserState {
    public func editableSiteStyleHost(of tab: BrowserTab) -> String? {
        guard currentTab === tab, !tab.isPrivate else { return nil }
        return SiteStyles.host(of: tab.url)
    }

    public func editSiteStyle(of tab: BrowserTab) {
        siteStyleHost = editableSiteStyleHost(of: tab)
    }

    public func siteStyle(for host: String) -> String { siteStyles[host] ?? "" }

    public func saveSiteStyle(_ css: String, for host: String) throws {
        try siteStyles.set(css, for: host)
        for session in pool.sessions.values where !session.tab.isPrivate && SiteStyles.host(of: session.webView.url) == host {
            Task { await siteStyles.apply(to: session.webView, on: host, includingRemoval: true) }
        }
        siteStyleHost = nil
    }
}
#endif
