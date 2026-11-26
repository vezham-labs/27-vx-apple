import BrowserCore
import AppKit
import WebKit
import UniformTypeIdentifiers

extension Browser {
    func refreshGitHubPullRequests() {
        let space = currentSpace
        Task { await refreshGitHubPullRequests(in: space) }
    }

    func refreshGitHubPullRequests(in space: Space, existingFolderID: UUID? = nil) async {
        guard !space.isPrivate, let github = URL(string: "https://github.com/pulls") else { return }
        let silently = existingFolderID != nil
        let profileID = space.websiteProfileID
        let profileRevision = space.websiteProfileRevision
        if !silently { showToast("Refreshing GitHub pull requests…") }
        let cookies = await engine.cookies(for: library.browsingProfile(in: space), url: github)
        guard space.websiteProfileID == profileID, space.websiteProfileRevision == profileRevision else { return }
        do {
            guard let folder = try await space.refreshGitHubPullRequests(cookies: cookies, existingFolderID: existingFolderID) else { return }
            library.scheduleSave()
            if !silently { showToast("GitHub Pull Requests: \(folder.feed?.articles.count ?? 0) open") }
        } catch {
            if !silently { showToast("Sign in to GitHub in this Space to add Pull Requests") }
        }
    }

    var editableSiteStyleHost: String? {
        guard let tab = currentTab, !tab.isPrivate, !library.agents.isInAgentSpace(tab) else { return nil }
        return SiteStyles.host(of: tab.url)
    }

    var shapeableSiteHost: String? {
        guard let tab = currentTab, !library.agents.isInAgentSpace(tab) else { return nil }
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

    func exportSiteStyle(for host: String) {
        guard let data = library.siteStyles.exportData(for: host) else {
            showToast("Couldn’t export these Boosts")
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = host + ".arkboost"
        panel.allowedContentTypes = [UTType(filenameExtension: "arkboost") ?? .json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: .atomic)
            showToast("Exported Boosts for \(host)")
        } catch { showToast("Couldn’t export these Boosts") }
    }

    func importSiteStyle() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "arkboost") ?? .json, .json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            guard let host = try library.siteStyles.importData(Data(contentsOf: url)) else {
                showToast("That file isn’t an Ark Boost")
                return
            }
            applySiteStyle(for: host)
            if host == editableSiteStyleHost { closeSiteStyleEditor() }
            showToast("Imported Boosts for \(host)")
        } catch { showToast("Couldn’t import those Boosts") }
    }

    func previewSiteElement(_ selector: String?) {
        guard let host = editableSiteStyleHost, let view = currentController?.page.view as? WKWebView else { return }
        Task { await library.siteStyles.apply(to: view, on: host, includingRemoval: true, showing: selector) }
    }

    @discardableResult
    func selectSiteElementToHide() -> RegionCaptureView? {
        guard let host = editableSiteStyleHost, let tab = currentTab, let url = tab.url,
              let view = currentController?.page.view as? WKWebView else { return nil }
        let picker = RegionCaptureView.present(on: view, mode: .element, relatedCount: { [weak self, weak view] point in
            guard let self, let view, currentTab === tab, tab.url == url, editableSiteStyleHost == host,
                  library.existingController(for: tab)?.page.view === view else { return nil }
            let selection = await PageCaptureImage.selection(at: point, in: view)
            guard currentTab === tab, tab.url == url, editableSiteStyleHost == host,
                  library.existingController(for: tab)?.page.view === view else { return nil }
            return selection?.relatedCount
        }) { [weak self, weak view] selection in
            guard case .element(let point, let allRelated) = selection, let self, let view,
                  currentTab === tab, tab.url == url else { return }
            Task { [weak self] in
                let selection = await PageCaptureImage.selection(at: point, in: view)
                guard let self, currentTab === tab, tab.url == url, editableSiteStyleHost == host,
                      library.existingController(for: tab)?.page.view === view else { return }
                guard let selection else { showToast("Couldn’t hide this element"); return }
                do {
                    let element: HiddenSiteElement
                    if allRelated {
                        guard let family = selection.family, !family.isEmpty, selection.relatedCount > 1 else {
                            showToast("No related elements found")
                            return
                        }
                        element = HiddenSiteElement(selector: family,
                                                    label: "All like \(selection.label) (\(selection.relatedCount))",
                                                    note: selection.note)
                    } else {
                        element = HiddenSiteElement(selector: selection.selector, label: selection.label,
                                                    note: selection.note, fingerprint: selection.fingerprint,
                                                    family: selection.family)
                    }
                    try library.siteStyles.hide(element, for: host)
                    applySiteStyle(for: host)
                    showToast("Hidden: \(element.label)", actions: [ToastAction(title: "Undo") { [weak self] in
                        do { try self?.restoreSiteElement(element.selector, for: host) }
                        catch { self?.showToast("Couldn’t restore this element") }
                    }])
                } catch { showToast("Couldn’t save the hidden element") }
            }
        }
        if picker != nil { showToast("Click to hide · Option-click for related elements · Esc to cancel") }
        return picker
    }

    @discardableResult
    func selectSiteElementToShape() -> RegionCaptureView? {
        guard let host = shapeableSiteHost, let tab = currentTab, let url = tab.url,
              let view = currentController?.page.view as? WKWebView else { return nil }
        let picker = RegionCaptureView.present(on: view, mode: .shape) { [weak self, weak view] result in
            guard case .shape(let point, let delta, let resize) = result, let self, let view,
                  currentTab === tab, tab.url == url else { return }
            Task { [weak self] in
                let selection = await PageCaptureImage.selection(at: point, in: view, requireFingerprint: true)
                let rect = resize ? await PageCaptureImage.element(at: point, in: view) : nil
                guard let self, currentTab === tab, tab.url == url, shapeableSiteHost == host,
                      library.existingController(for: tab)?.page.view === view,
                      let selection, selection.fingerprint?.isEmpty == false else { return }
                let scale = max(view.pageZoom, 0.01)
                let dx = Double(delta.x / scale), dy = Double(delta.y / scale)
                guard abs(dx) + abs(dy) >= 2 else { return }
                let store: SiteStyles
                if tab.isPrivate {
                    if let existing = library.privateSiteShapes[tab.id] { store = existing }
                    else { store = SiteStyles(fileURL: nil); library.privateSiteShapes[tab.id] = store }
                } else { store = library.siteStyles }
                let previous = store.hiddenElements(for: host).first { $0.selector == selection.selector }
                let oldShape = previous?.shape
                var element = HiddenSiteElement(selector: selection.selector, label: selection.label,
                                                note: selection.note, fingerprint: selection.fingerprint, family: selection.family)
                if resize, let rect {
                    element.shape = .init(width: max(1, Double(rect.width / scale) + dx), height: max(1, Double(rect.height / scale) + dy),
                                          dx: oldShape?.dx, dy: oldShape?.dy)
                } else if !resize {
                    element.shape = .init(width: oldShape?.width, height: oldShape?.height,
                                          dx: (oldShape?.dx ?? 0) + dx, dy: (oldShape?.dy ?? 0) + dy)
                }
                else { showToast("Couldn’t resize this element"); return }
                do {
                    try store.shape(element, for: host)
                    if tab.isPrivate { await store.apply(to: view, on: host) } else { applySiteStyle(for: host) }
                    showToast(tab.isPrivate ? "Changed for this private tab" : (resize ? "Element resized" : "Element moved"), actions: [ToastAction(title: "Undo") { [weak self, weak view] in
                        guard let self else { return }
                        do {
                            try store.restore(element.selector, for: host)
                            if let previous {
                                if previous.shape == nil { try store.hide(previous, for: host) }
                                else { try store.shape(previous, for: host) }
                            }
                            if tab.isPrivate, let view { Task { await store.apply(to: view, on: host, includingRemoval: true) } }
                            else if !tab.isPrivate { applySiteStyle(for: host) }
                        } catch { showToast("Couldn’t undo this change") }
                    }])
                } catch { showToast("Couldn’t save this change") }
            }
        }
        if picker != nil { showToast("Drag an element to move · Option-drag to resize · Esc to cancel") }
        return picker
    }

    private func applySiteStyle(for host: String) {
        for controller in library.controllers.values where !controller.tab.isPrivate
            && !library.agents.isInAgentSpace(controller.tab) && SiteStyles.host(of: controller.tab.url) == host {
            if let view = controller.page?.view as? WKWebView {
                Task { await library.siteStyles.apply(to: view, on: host, includingRemoval: true) }
            }
        }
        for window in library.windows {
            guard let glance = window.glance, glance.allowsSiteStyles,
                  SiteStyles.host(of: glance.url) == host, let view = glance.page.view as? WKWebView else { continue }
            Task { await library.siteStyles.apply(to: view, on: host, includingRemoval: true) }
        }
    }
}
