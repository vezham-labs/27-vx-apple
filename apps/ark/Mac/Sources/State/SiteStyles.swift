import BrowserCore
import WebKit

extension Browser {
    var editableSiteStyleHost: String? {
        guard let tab = currentTab, !tab.isPrivate, !library.agents.isInAgentSpace(tab) else { return nil }
        return SiteStyles.host(of: tab.url)
    }

    func editSiteStyle() {
        siteStyleHost = editableSiteStyleHost
    }

    func saveSiteStyle(_ css: String, for host: String) throws {
        try library.siteStyles.set(css, for: host)
        for controller in library.controllers.values where !controller.tab.isPrivate
            && !library.agents.isInAgentSpace(controller.tab) && SiteStyles.host(of: controller.tab.url) == host {
            if let view = controller.page?.view as? WKWebView {
                Task { await library.siteStyles.apply(to: view, on: host, includingRemoval: true) }
            }
        }
        siteStyleHost = nil
    }
}
