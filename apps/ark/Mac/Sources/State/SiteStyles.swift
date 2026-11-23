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
        applySiteStyle(for: host)
        siteStyleHost = nil
    }

    func restoreSiteElement(_ selector: String, for host: String) throws {
        try library.siteStyles.restore(selector, for: host)
        applySiteStyle(for: host)
    }

    @discardableResult
    func selectSiteElementToHide() -> RegionCaptureView? {
        guard let host = editableSiteStyleHost, let tab = currentTab, let url = tab.url,
              let view = currentController?.page.view as? WKWebView else { return nil }
        let picker = RegionCaptureView.present(on: view, mode: .element) { [weak self, weak view] selection in
            guard case .element(let point) = selection, let self, let view,
                  currentTab === tab, tab.url == url else { return }
            Task { [weak self] in
                let selector = await siteElementSelector(at: point, in: view)
                guard let self, currentTab === tab, tab.url == url, editableSiteStyleHost == host,
                      library.existingController(for: tab)?.page.view === view else { return }
                guard let selector else { showToast("Couldn’t hide this element"); return }
                do {
                    try library.siteStyles.hide(selector, for: host)
                    applySiteStyle(for: host)
                    showToast("Element hidden", actions: [ToastAction(title: "Undo") { [weak self] in
                        do { try self?.restoreSiteElement(selector, for: host) }
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

@MainActor
private func siteElementSelector(at point: CGPoint, in webView: WKWebView) async -> String? {
    try? await webView.callAsyncJavaScript("""
        const viewport = window.visualViewport;
        const scale = pageZoom * (viewport?.scale ?? 1);
        const element = document.elementFromPoint(x / scale + (viewport?.offsetLeft ?? 0),
                                                  y / scale + (viewport?.offsetTop ?? 0));
        if (!element || element === document.body || element === document.documentElement) return null;
        const parts = [];
        for (let node = element; node && node !== document.body; node = node.parentElement) {
            if (node.id) {
                const id = '#' + CSS.escape(node.id);
                if (document.querySelectorAll(id).length === 1) return [id, ...parts].join(' > ');
            }
            let index = 1;
            for (let sibling = node.previousElementSibling; sibling; sibling = sibling.previousElementSibling) {
                if (sibling.localName === node.localName && sibling.namespaceURI === node.namespaceURI) index++;
            }
            parts.unshift(`${CSS.escape(node.localName)}:nth-of-type(${index})`);
        }
        const selector = ['body', ...parts].join(' > ');
        return document.querySelector(selector) === element ? selector : null;
        """, arguments: ["x": point.x, "y": point.y, "pageZoom": webView.pageZoom],
        in: nil, contentWorld: .world(name: "ark.site-style")) as? String
}
