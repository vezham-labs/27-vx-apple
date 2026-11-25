import BrowserCore
import WebKit

extension Browser {
    var editableSiteStyleHost: String? {
        guard let tab = currentTab, !tab.isPrivate, !library.agents.isInAgentSpace(tab) else { return nil }
        return SiteStyles.host(of: tab.url)
    }

    func editSiteStyle() {
        siteStyleHost = editableSiteStyleHost
        isSiteStyleEditorPresented = siteStyleHost != nil
    }

    func closeSiteStyleEditor() {
        isSiteStyleEditorPresented = false
        siteStyleHost = nil
    }

    func saveSiteStyle(_ css: String, font: SiteStyleFont = .original, for host: String) throws {
        try library.siteStyles.set(css, for: host)
        try library.siteStyles.setFont(font, for: host)
        applySiteStyle(for: host)
        closeSiteStyleEditor()
    }

    func saveSiteStyle(_ css: String, font: SiteStyleFont, accent: String?, for host: String) throws {
        try library.siteStyles.set(css, for: host)
        try library.siteStyles.setFont(font, for: host)
        try library.siteStyles.setAccent(accent, for: host)
        applySiteStyle(for: host)
        closeSiteStyleEditor()
    }

    func restoreSiteElement(_ selector: String, for host: String) throws {
        try library.siteStyles.restore(selector, for: host)
        applySiteStyle(for: host)
    }

    func restoreAllSiteElements(for host: String) throws {
        try library.siteStyles.restoreAll(for: host)
        applySiteStyle(for: host)
    }

    func previewSiteElement(_ selector: String?) {
        guard let host = editableSiteStyleHost, let view = currentController?.page.view as? WKWebView else { return }
        Task { await library.siteStyles.apply(to: view, on: host, includingRemoval: true, showing: selector) }
    }

    @discardableResult
    func selectSiteElementToHide() -> RegionCaptureView? {
        guard let host = editableSiteStyleHost, let tab = currentTab, let url = tab.url,
              let view = currentController?.page.view as? WKWebView else { return nil }
        let picker = RegionCaptureView.present(on: view, mode: .element) { [weak self, weak view] selection in
            guard case .element(let point) = selection, let self, let view,
                  currentTab === tab, tab.url == url else { return }
            Task { [weak self] in
                let selection = await PageCaptureImage.selection(at: point, in: view)
                guard let self, currentTab === tab, tab.url == url, editableSiteStyleHost == host,
                      library.existingController(for: tab)?.page.view === view else { return }
                guard let selection else { showToast("Couldn’t hide this element"); return }
                do {
                    try library.siteStyles.hide(HiddenSiteElement(selector: selection.selector, label: selection.label,
                                                                  note: selection.note), for: host)
                    applySiteStyle(for: host)
                    showToast("Hidden: \(selection.label)", actions: [ToastAction(title: "Undo") { [weak self] in
                        do { try self?.restoreSiteElement(selection.selector, for: host) }
                        catch { self?.showToast("Couldn’t restore this element") }
                    }])
                } catch { showToast("Couldn’t save the hidden element") }
            }
        }
        if picker != nil { showToast("Click an element to hide it · Esc to cancel") }
        return picker
    }

    private func applySiteStyle(for host: String) {
        for controller in library.controllers.values where !controller.tab.isPrivate
            && !library.agents.isInAgentSpace(controller.tab) && SiteStyles.host(of: controller.tab.url) == host {
            if let view = controller.page?.view as? WKWebView {
                Task { await library.siteStyles.apply(to: view, on: host, includingRemoval: true) }
            }
        }
    }
}
