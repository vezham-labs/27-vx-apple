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

    public func hiddenSiteElements(for host: String) -> [HiddenSiteElement] { siteStyles.hiddenElements(for: host) }

    public func saveSiteStyle(_ css: String, for host: String) throws {
        try siteStyles.set(css, for: host)
        for session in pool.sessions.values where !session.tab.isPrivate && SiteStyles.host(of: session.webView.url) == host {
            Task { await siteStyles.apply(to: session.webView, on: host, includingRemoval: true) }
        }
        siteStyleHost = nil
    }

    public func restoreSiteElement(_ selector: String, for host: String) throws {
        try siteStyles.restore(selector, for: host)
        for session in pool.sessions.values where !session.tab.isPrivate && SiteStyles.host(of: session.webView.url) == host {
            Task { await siteStyles.apply(to: session.webView, on: host, includingRemoval: true) }
        }
    }

    public func restoreAllSiteElements(for host: String) throws {
        try siteStyles.restoreAll(for: host)
        for session in pool.sessions.values where !session.tab.isPrivate && SiteStyles.host(of: session.webView.url) == host {
            Task { await siteStyles.apply(to: session.webView, on: host, includingRemoval: true) }
        }
    }

    public func previewSiteElement(_ selector: String?, for host: String) {
        guard let tab = currentTab, !tab.isPrivate, SiteStyles.host(of: tab.url) == host,
              let session = pool.sessions.values.first(where: { $0.tab === tab }) else { return }
        Task { await siteStyles.apply(to: session.webView, on: host, includingRemoval: true, showing: selector) }
    }

    public func hideSiteElement(at point: CGPoint, of tab: BrowserTab) {
        guard pageCaptureMode(of: tab) == .hideElement, currentTab === tab, !tab.isPrivate,
              let url = tab.url, let host = SiteStyles.host(of: url) else { return }
        cancelPageCapture(of: tab)
        let webView = session(for: tab).webView
        Task {
            guard let selection = await PageCaptureImage.selection(at: point, in: webView),
                  currentTab === tab, tab.url == url else {
                showToast("Couldn’t select that page element")
                return
            }
            do {
                try siteStyles.hide(HiddenSiteElement(selector: selection.selector, label: selection.label,
                                                      note: selection.note), for: host)
                await siteStyles.apply(to: webView, on: host, includingRemoval: true)
                showToast("Hidden: \(selection.label)")
            } catch {
                showToast("Couldn’t save the site style")
            }
        }
    }
}
#endif
