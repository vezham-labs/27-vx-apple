import AppKit
import SwiftUI
import BrowserCore
import BrowserEngine
import Suggest

extension Browser {
    // MARK: Command bar

    func showCommandBar(_ mode: CommandBarMode) {
        // Editing needs a page; with none it's just a new tab.
        commandBar = mode == .editCurrent && currentTab == nil ? .newTab : mode
    }

    /// A picked suggestion, favourite or Return in the command bar.
    func perform(_ action: SuggestionAction, mode: CommandBarMode, source: Frecency.VisitSource = .typed,
                 rememberTypedAddress: Bool = false) {
        commandBar = nil
        switch action {
        case .switchToTab(let id, _):
            if let tab = spaces.flatMap(\.allTabs).first(where: { $0.id == id }) { select(tab) }
            else if let tab = archive.first(where: { $0.id == id }) { restoreFromArchive(tab) }
        case .open(let url):
            navigate(to: url, replacing: mode == .editCurrent, source: source, rememberTypedAddress: rememberTypedAddress)
        case .search(let q):
            // "!yt cats" goes straight to YouTube, even when it arrives as a plain search.
            let url = Bangs.resolve(q)?.url ?? settings.searchEngine.searchURL(for: q)
            navigate(to: url, replacing: mode == .editCurrent, source: source)
        case .command(let id):
            run(command: id)
        }
    }

    /// A deliberately typed URL for another installed app (for example `vnc://` or `ssh://`).
    /// Keep unknown schemes as web searches unless Launch Services identifies a different app.
    /// Page initiated handoffs use the separate permission flow in `Browser.handOff`.
    func handOffTypedAppAddress(_ typed: String) -> Bool {
        let text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(where: \.isWhitespace),
              let delimiter = text.range(of: "://") else { return false }
        let scheme = String(text[..<delimiter.lowerBound]).lowercased()
        let webKitSchemes: Set<String> = ["http", "https", "file", "about", "data", "ark"]
        guard !webKitSchemes.contains(scheme), !["javascript", "blob"].contains(scheme),
              scheme.first?.isLetter == true,
              scheme.allSatisfy({ $0.isLetter || $0.isNumber || "+-.".contains($0) }),
              let url = URL(string: text), url.scheme?.lowercased() == scheme,
              let appURL = NSWorkspace.shared.urlForApplication(toOpen: url),
              Bundle(url: appURL)?.bundleIdentifier != Bundle.main.bundleIdentifier,
              NSWorkspace.shared.open(url) else { return false }
        commandBar = nil
        return true
    }

    @discardableResult
    func navigate(to url: URL, replacing: Bool, source: Frecency.VisitSource, rememberTypedAddress: Bool = false) -> BrowserTab? {
        if LibraryPage.isLibrary(url) { openLibrary(LibraryPage.target(url)); return nil }
        if replacing, let tab = currentTab {
            if isReaderShowing { closeReader() }
            controller(for: tab).load(url, source: source, rememberTypedAddress: rememberTypedAddress)
            return tab
        } else {
            let tab = newTab(url: url, source: source)
            if rememberTypedAddress { controller(for: tab).rememberTypedAddress(url) }
            return tab
        }
    }

    /// Return a pinned tab to the URL it had when first pinned.
    func returnToPinnedPage(_ tab: BrowserTab) {
        guard tab.isPinned, let home = tab.pinnedHomeURL, let current = tab.url,
              URLNormalizer.key(for: home) != URLNormalizer.key(for: current) else { return }
        select(tab)
        library.controller(for: tab).load(home, source: .typed)
    }

    /// Commands that make sense right now, matched by what you type in the command bar.
    func availableCommands() -> [BrowserCommand] {
        var out: [BrowserCommand] = []
        if let tab = currentTab {
            if !tab.isPrivate {
                out.append(BrowserCommand(id: "pin", title: tab.isPinned ? "Unpin Tab" : "Pin Tab", keywords: ["tab"]))
            }
            if let url = tab.url, !isFavorite(url) {
                out.append(BrowserCommand(id: "favourite", title: "Add to Favourites", subtitle: tab.displayTitle,
                                          keywords: ["favorite", "star", "bookmark"]))
            }
            out.append(BrowserCommand(id: "close", title: "Close Tab", keywords: ["tab"]))
            if let url = tab.url {
                out.append(BrowserCommand(id: "copy-link", title: "Copy Link", subtitle: linkForCopy(url).absoluteString, keywords: ["url", "share"]))
                out.append(BrowserCommand(id: "copy-markdown", title: "Copy Link as Markdown", keywords: ["url", "md", "share"]))
                out.append(BrowserCommand(id: "copy-page-image", title: "Copy Full Page Image", keywords: ["capture", "screenshot", "png"]))
                out.append(BrowserCommand(id: "copy-page-area", title: "Copy Page Area…", keywords: ["capture", "region", "screenshot", "png"]))
                out.append(BrowserCommand(id: "copy-page-element", title: "Copy Page Element…", keywords: ["capture", "element", "screenshot", "png"]))
                out.append(BrowserCommand(id: "save-page-image", title: "Save Full Page Image…", keywords: ["capture", "screenshot", "png"]))
                out.append(BrowserCommand(id: "save-page-area", title: "Save Page Area…", keywords: ["capture", "region", "screenshot", "png"]))
                out.append(BrowserCommand(id: "save-page-element", title: "Save Page Element…", keywords: ["capture", "element", "screenshot", "png"]))
                out.append(BrowserCommand(id: "reload", title: "Reload Page", keywords: ["refresh"]))
                out.append(BrowserCommand(id: "toggle-reload-cache", title: reloadWithoutCacheForCurrentSite ? "Use Cache for Site Reloads" : "Reload This Site Without Cache", keywords: ["developer", "cache", "refresh"]))
                out.append(BrowserCommand(id: "find", title: "Find on Page", keywords: ["search", "text"]))
                out.append(BrowserCommand(id: "reader", title: isReaderShowing ? "Hide Reader" : "Show Reader",
                                          keywords: ["article", "reading", "clean"]))
                out.append(BrowserCommand(id: ShortcutAction.pictureInPicture.rawValue,
                                          title: ShortcutAction.pictureInPicture.title,
                                          keywords: ["video", "float", "mini player", "pip"]))
                out.append(BrowserCommand(id: "mini-player", title: "Mini Player",
                                          keywords: ["video", "float", "mini player", "controls"]))
                out.append(BrowserCommand(id: "tab-window", title: "Move Tab to New Window", keywords: ["window", "detach"]))
                out.append(BrowserCommand(id: "zoom-in", title: "Zoom In", keywords: ["bigger", "larger", "text size"]))
                out.append(BrowserCommand(id: "zoom-out", title: "Zoom Out", keywords: ["smaller", "text size"]))
                out.append(BrowserCommand(id: "zoom-reset", title: "Actual Size", keywords: ["zoom", "reset"]))
                out.append(BrowserCommand(id: "blockers", title: blockingDisabledForCurrentSite ? "Turn Blockers On for This Site" : "Turn Blockers Off for This Site",
                                          keywords: ["ads", "adblock", "trackers", "content blocker"]))
                out.append(BrowserCommand(id: "share", title: "Share…", keywords: ["send"]))
                if library.developerTools {
                    out.append(BrowserCommand(id: "inspector", title: "Web Inspector", keywords: ["developer", "devtools", "inspect", "console"]))
                }
            }
            for s in regularSpaces where s.id != selectedSpaceID && !tab.isPrivate {
                out.append(BrowserCommand(id: "move:" + s.id.uuidString, title: "Move Tab to \(s.name)", subtitle: "Space", keywords: ["space"]))
            }
        }
        if today(in: currentSpace).count > 1 {
            out.append(BrowserCommand(id: "close-others", title: "Close Other Tabs", keywords: ["tabs", "clean"]))
        }
        if lastUsedTab != nil {
            out.append(BrowserCommand(id: ShortcutAction.lastUsedTab.rawValue, title: ShortcutAction.lastUsedTab.title, keywords: ["previous", "recent", "switch"]))
        }
        if orderedTabs.count > 1 {
            out.append(BrowserCommand(id: ShortcutAction.recentTabs.rawValue, title: ShortcutAction.recentTabs.title,
                                      keywords: ["switch", "preview", "tab"]))
        }
        if canExportSpaceLinks {
            out.append(BrowserCommand(id: "export-space-links", title: "Export Space Links…", keywords: ["save", "tabs", "bookmarks", "json"]))
        }
        out.append(BrowserCommand(id: "export-all-spaces", title: "Export All Spaces as Bookmarks…", keywords: ["save", "tabs", "bookmarks", "html"]))
        if !currentSpace.isPrivate {
            out.append(BrowserCommand(id: "github-pull-requests", title: "GitHub Pull Requests Live Folder", subtitle: "Sidebar", keywords: ["github", "pull", "review", "live folder"]))
        }
        out.append(BrowserCommand(id: "import-space-links", title: "Import Space Links…", keywords: ["restore", "tabs", "bookmarks", "json"]))
        if let host = editableSiteStyleHost {
            out.append(BrowserCommand(id: "edit-site-style", title: "Edit Boosts…", subtitle: host, keywords: ["css", "site style", "customize"]))
            out.append(BrowserCommand(id: "hide-site-element", title: "Hide Page Element…", keywords: ["boost", "element", "customize"]))
        }
        if shapeableSiteHost != nil { out.append(BrowserCommand(id: "shape-site-element", title: "Move or Resize Page Element…", keywords: ["boost", "element", "customize"])) }
        if !splitCandidates.isEmpty {
            out.append(BrowserCommand(id: "split-view", title: "Split View With…", keywords: ["pane", "side by side", "stack"]))
        }
        if activeSplit != nil {
            out.append(BrowserCommand(id: "separate-split", title: "Separate Split Tabs", keywords: ["pane", "unsplit"]))
        }
        if !clearableTodayTabs(in: currentSpace).isEmpty {
            out.append(BrowserCommand(id: "clear-today", title: "Clear Today's Tabs", keywords: ["tabs", "clean", "close all"]))
        }
        if let last = recentlyClosed.last {
            out.append(BrowserCommand(id: "reopen", title: "Reopen Closed Tab", subtitle: last.displayTitle, keywords: ["undo", "restore"]))
        }
        out.append(BrowserCommand(id: "sidebar", title: isSidebarDocked ? "Hide Sidebar" : "Show Sidebar", keywords: ["toggle"]))
        out.append(BrowserCommand(id: "new-window", title: "New Window", keywords: ["window"]))
        out.append(BrowserCommand(id: "private", title: "New Private Tab", keywords: ["incognito"]))
        if let p = privateSpace {
            out.append(BrowserCommand(id: "close-private", title: "Close Private Tabs", subtitle: "\(p.allTabs.count) tabs",
                                      keywords: ["incognito", "private", "clear"]))
        }
        for s in spaces where s.id != selectedSpaceID {
            out.append(BrowserCommand(id: "space:" + s.id.uuidString, title: "Switch to \(s.name)", subtitle: "Space", keywords: ["space"]))
        }
        out.append(BrowserCommand(id: "new-space", title: "New Space", keywords: ["space", "profile"]))
        if !downloads.isEmpty {
            out.append(BrowserCommand(id: "downloads", title: "Show Downloads", subtitle: "\(downloads.count) files", keywords: ["files"]))
        }
        out.append(BrowserCommand(id: "archive", title: "Show Archive", subtitle: "\(archive.count) archived tabs", keywords: ["history", "closed"]))
        out.append(BrowserCommand(id: "library", title: "Library", keywords: ["extensions", "plugins", "add-ons", "packs", "manage extensions"]))
        out.append(BrowserCommand(id: "settings", title: "Settings", keywords: ["preferences", "search engine"]))
        out.append(BrowserCommand(id: "panel", title: panel == nil ? "Show Panel" : "Hide Panel", keywords: ["right", "side", "tools"]))
        // Every extension with a toolbar button.
        let page = currentController?.page
        for ext in library.actionExtensions {
            let badge = library.actionState(ext, for: page)?.badgeText ?? ""
            out.append(BrowserCommand(id: "ext:" + ext.id, title: "Extension: \(ext.name)", subtitle: badge.isEmpty ? nil : badge,
                                      keywords: ["extension", "add-on"]))
        }
        // Tools add their own: "Open Radar", "Stop All Agents"…
        for (tool, command) in library.workbench.commands {
            out.append(BrowserCommand(id: Workbench.commandID(tool, command), title: command.title,
                                      subtitle: command.subtitle, keywords: command.keywords + [tool.title]))
        }
        return out
    }

    /// The icon a command row shows: the tool's own, or a generic one.
    func symbol(forCommand id: String) -> String {
        if id.hasPrefix("tool:") {
            let parts = id.split(separator: ":", maxSplits: 2).map(String.init)
            if parts.count == 3, let entry = library.workbench.commands.first(where: { $0.tool.id == parts[1] && $0.command.id == parts[2] }) {
                return entry.command.symbol ?? entry.tool.symbol
            }
        }
        return Self.commandSymbols[id.split(separator: ":").first.map(String.init) ?? id] ?? "command"
    }

    private static let commandSymbols: [String: String] = [
        "pin": "pin", "favourite": "star", "close": "xmark", "copy-link": "link", "copy-text": "equal.circle", "reload": "arrow.clockwise",
        "find": "text.magnifyingglass", "reader": "doc.plaintext", "tab-window": "macwindow.badge.plus",
        "new-window": "macwindow", "zoom-in": "plus.magnifyingglass", "zoom-out": "minus.magnifyingglass",
        "zoom-reset": "1.magnifyingglass", "blockers": "shield", "share": "square.and.arrow.up",
        "close-others": "xmark.square", "reopen": "arrow.uturn.backward", "sidebar": "sidebar.left",
        "panel": "sidebar.right", "private": "eye.slash", "close-private": "eye.slash", "new-space": "plus.rectangle.on.rectangle",
        "downloads": "arrow.down.circle", "archive": "archivebox", "settings": "gearshape", "library": "square.grid.2x2", "space": "square.stack",
        "move": "arrow.right.square", "restore": "archivebox", "ext": "puzzlepiece.extension",
        "copy-markdown": "link.badge.plus", "copy-page-image": "camera.viewfinder", "copy-page-area": "viewfinder",
        "copy-page-element": "scope",
        "clear-today": "xmark.circle", "inspector": "hammer", "mini-player": "pip.enter",
    ]

    func run(command id: String) {
        commandBar = nil
        if library.workbench.run(commandID: id, in: self) { return }
        if id.hasPrefix("copy-text:") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(String(id.dropFirst("copy-text:".count)), forType: .string)
            showToast("Copied \(id.dropFirst("copy-text:".count))")
            return
        }
        if id.hasPrefix("ext:"), let ext = library.actionExtensions.first(where: { $0.id == String(id.dropFirst(4)) }) {
            runExtension(ext, anchor: nil)
            return
        }
        switch id {
        case "panel": togglePanel()
        case "pin": if let t = currentTab { togglePinned(t) }
        case "favourite": if let t = currentTab, let url = t.url { addFavorite(url: url, title: t.displayTitle) }
        case "close": if let t = currentTab { close(t) }
        case "copy-link": copyCurrentLink()
        case "copy-markdown": copyCurrentLinkAsMarkdown()
        case "copy-page-image": copyFullPageImage()
        case "copy-page-area": selectPageArea()
        case "copy-page-element": selectPageElement()
        case "toggle-reload-cache": toggleReloadWithoutCacheForCurrentSite()
        case "save-page-image": copyFullPageImage(save: true)
        case "save-page-area": selectPageArea(save: true)
        case "save-page-element": selectPageElement(save: true)
        case ShortcutAction.lastUsedTab.rawValue: selectLastUsedTab()
        case ShortcutAction.recentTabs.rawValue: showRecentTabs()
        case "export-space-links": exportSpaceLinks()
        case "export-all-spaces": exportAllSpacesBookmarks()
        case "import-space-links": importSpaceLinks()
        case "github-pull-requests": refreshGitHubPullRequests()
        case "edit-site-style": editSiteStyle()
        case "hide-site-element": selectSiteElementToHide()
        case "shape-site-element": selectSiteElementToShape()
        case "split-view": isSplitPickerPresented = true
        case "separate-split": separateSplit()
        case "clear-today": withAnimation(Motion.snappy) { clearToday() }
        case "inspector": showWebInspector()
        case "reload": reload()
        case "find": showFind()
        case "reader": toggleReader()
        case "tab-window": if let t = currentTab { openInNewWindow(t) }
        case "new-window": library.openWindow()
        case "zoom-in": zoom(1)
        case "zoom-out": zoom(-1)
        case "zoom-reset": zoom(0)
        case "blockers": toggleBlockingForCurrentSite()
        case ShortcutAction.pictureInPicture.rawValue:
            if let tab = currentTab { library.videoPictureInPicture.toggle(for: tab, in: self) }
        case "mini-player":
            if let tab = currentTab { library.videoMiniPlayer.toggle(for: tab, in: self) }
        case "share": shareCurrentPage()
        case "close-others": if let t = currentTab { closeOtherTabs(than: t) }
        case "reopen": reopenClosedTab()
        case "sidebar": toggleSidebar()
        case "private": newTab(url: nil, isPrivate: true); showCommandBar(.editCurrent)
        case "close-private": closePrivateSpace()
        case "new-space": addSpace()
        case "downloads": showPanel("downloads")
        case "archive": isArchivePresented = true
        case "library": openLibrary()
        case "settings": library.openSettings()
        default:
            if id.hasPrefix("space:"), let uuid = UUID(uuidString: String(id.dropFirst(6))),
               let s = spaces.first(where: { $0.id == uuid }) {
                selectSpace(s)
            } else if id.hasPrefix("move:"), let uuid = UUID(uuidString: String(id.dropFirst(5))),
                      let s = spaces.first(where: { $0.id == uuid }), let t = currentTab {
                move(t, to: s)
                showToast("Moved to \(s.name)")
            } else if id.hasPrefix("restore:"), let uuid = UUID(uuidString: String(id.dropFirst(8))),
                      let t = archive.first(where: { $0.id == uuid }) {
                restoreFromArchive(t)
            }
        }
    }

    // MARK: Page actions

    /// The URL the user should see or copy. WebKit can keep showing the last
    /// committed page after a provisional navigation fails.
    var currentAddress: URL? {
        if let failed = currentTab?.loadError?.url,
           let scheme = failed.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            return failed
        }
        return currentTab?.url
    }

    func goBack() {
        if isReaderShowing { closeReader(); return }
        currentController?.page.goBack()
    }
    func goForward() { currentController?.page.goForward() }

    func reload() {
        guard let c = currentController else { return }
        if let failedURL = c.tab.loadError?.url {
            c.load(failedURL, source: .typed)
            return
        }
        c.tab.loadError = nil
        if reloadWithoutCacheForCurrentSite { c.page.reloadFromOrigin() }
        else { c.page.reload() }
    }

    private var currentReloadHost: String? {
        guard let url = currentTab?.url, let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme), let host = url.host()?.lowercased(), !host.isEmpty else { return nil }
        return host
    }

    var reloadWithoutCacheForCurrentSite: Bool {
        guard let tab = currentTab, let host = currentReloadHost else { return false }
        return tab.isPrivate ? library.privateReloadWithoutCacheSites.contains("\(tab.id.uuidString):\(host)") : library.reloadWithoutCacheHosts.contains(host)
    }

    func toggleReloadWithoutCacheForCurrentSite() {
        guard let tab = currentTab, let host = currentReloadHost else { return }
        if tab.isPrivate {
            let key = "\(tab.id.uuidString):\(host)"
            if !library.privateReloadWithoutCacheSites.insert(key).inserted { library.privateReloadWithoutCacheSites.remove(key) }
        } else {
            if !library.reloadWithoutCacheHosts.insert(host).inserted { library.reloadWithoutCacheHosts.remove(host) }
        }
    }

    func visitAnyway() { currentController?.visitAnyway() }

    func reloadFromOrigin() { currentController?.page.reloadFromOrigin() }
    func stopLoading() { currentController?.stopLoading() }

    /// Cmd-+ / Cmd-- / Cmd-0. Remembered per site.
    func zoom(_ direction: Int) {
        if isReaderShowing { reader?.zoom(by: direction); return }
        guard engine.info.capabilities.contains(.pageZoom), currentTab?.url != nil else { return }
        currentController?.zoom(by: direction)
    }

    /// Read from the tab, which is observable, so the address bar's badge follows ⌘+ and ⌘− without a redraw.
    var currentZoom: Double { currentTab?.pageZoom ?? 1 }

    func copyCurrentLink() {
        guard let url = currentAddress else { return }
        if currentTab?.loadError?.url == url {
            copyLinkExactly(url)
            showToast("Address copied")
            return
        }
        copyLink(url)
        showToast("Link copied")
    }

    private func copyLinkExactly(_ url: URL, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.setString(url.absoluteString, forType: .string)
    }

    func copyLink(_ url: URL, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.setString(linkForCopy(url).absoluteString, forType: .string)
    }

    /// `[Title](url)`, like Arc's ⌥⇧⌘C.
    func copyCurrentLinkAsMarkdown() {
        guard let tab = currentTab, let url = currentAddress else { return }
        let title = tab.displayTitle.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
        let copied = tab.loadError?.url == url ? url : linkForCopy(url)
        let link = copied.absoluteString.replacingOccurrences(of: "(", with: "%28").replacingOccurrences(of: ")", with: "%29")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("[\(title)](\(link))", forType: .string)
        showToast("Markdown link copied")
    }

    private func linkForCopy(_ url: URL) -> URL {
        settings.cleanLinks ? LinkCleaner.cleaned(url) : url
    }

    /// ⌥⌘I. WebKit has no public call to open the inspector, so this uses the one Safari's
    /// Develop menu uses, and does nothing if it's ever gone.
    func showWebInspector() {
        guard currentTab?.url != nil, let view = currentController?.page.view else { return }
        guard library.developerTools else {
            showToast("Turn on Inspect Element in Settings › Engine")
            return
        }
        let getter = NSSelectorFromString("_inspector"), show = NSSelectorFromString("show")
        guard view.responds(to: getter),
              let inspector = view.perform(getter)?.takeUnretainedValue() as? NSObject,
              inspector.responds(to: show) else { return }
        inspector.perform(show)
    }

    /// An action's extra keys (⇧⌘] beside ⌥⌘↓, say), which the menu can't show, land here.
    func perform(_ action: ShortcutAction) {
        switch action {
        case .newTab: showCommandBar(.newTab)
        case .openLocation: showCommandBar(.editCurrent)
        case .commands: showCommandBar(.commands)
        case .newWindow: library.openWindow()
        case .privateTab: run(command: "private")
        case .close: if let t = currentTab { withAnimation(Motion.snappy) { close(t) } }
        case .reopen: reopenClosedTab()
        case .closeOthers: if let t = currentTab { closeOtherTabs(than: t) }
        case .clearToday: withAnimation(Motion.snappy) { clearToday() }
        case .nextTab: selectAdjacentTab(1)
        case .previousTab: selectAdjacentTab(-1)
        case .lastUsedTab: selectLastUsedTab()
        case .recentTabs: showRecentTabs()
        case .pin: if let t = currentTab, !t.isPrivate { withAnimation(Motion.snappy) { togglePinned(t) } }
        case .favourite: toggleFavoriteForCurrentTab()
        case .archive: isArchivePresented = true
        case .nextSpace: selectAdjacentSpace(1)
        case .previousSpace: selectAdjacentSpace(-1)
        case .nextProfile: selectAdjacentWebsiteProfile(1)
        case .previousProfile: selectAdjacentWebsiteProfile(-1)
        case .sidebar: toggleSidebar()
        case .panel: togglePanel()
        case .notes: showPanel("notes", toggles: true)
        case .downloads: showPanel("downloads", toggles: true)
        case .back: goBack()
        case .forward: goForward()
        case .reload: reload()
        case .hardReload: reloadFromOrigin()
        case .stop: stopLoading()
        case .find: showFind()
        case .findNext: findNext()
        case .findPrevious: findNext(backwards: true)
        case .copyLink: copyCurrentLink()
        case .copyMarkdown: copyCurrentLinkAsMarkdown()
        case .reader: toggleReader()
        case .inspector: showWebInspector()
        case .pictureInPicture:
            if let tab = currentTab { library.videoPictureInPicture.toggle(for: tab, in: self) }
        }
    }

    func shareCurrentPage() {
        guard let url = currentTab?.url, let view = currentController?.page.view else { return }
        let picker = NSSharingServicePicker(items: [url])
        picker.show(relativeTo: NSRect(x: view.bounds.midX, y: view.bounds.maxY - 1, width: 1, height: 1), of: view, preferredEdge: .minY)
    }

    func toggleFavoriteForCurrentTab() {
        guard let tab = currentTab, let url = tab.url else { return }
        let key = URLNormalizer.key(for: url)
        if let f = favorites.first(where: { URLNormalizer.key(for: $0.url) == key }) {
            removeFavorite(f)
            showToast("Removed from Favourites")
        } else {
            addFavorite(url: url, title: tab.displayTitle)
            showToast("Added to Favourites")
        }
    }

    // MARK: Find

    func showFind() {
        guard currentTab?.url != nil, !isReaderShowing else { return }
        if find == nil { find = FindState() }
        findFocusRequest = UUID()
    }

    func findNext(backwards: Bool = false) {
        // With the bar closed, Find Next opens it; with it open and empty, there's nothing to do.
        guard let text = find?.text else { showFind(); return }
        guard !text.isEmpty, let page = currentController?.page else { return }
        findPage = page
        Task { @MainActor in
            let found = await page.find(text, backwards: backwards)
            let matches = found ? await page.findMatches(text) : nil
            if find?.text == text {
                find?.found = found
                find?.matches = matches
            }
        }
    }

    func closeFind() {
        currentController?.page.clearFind()
        find = nil
    }

    /// Closes find when the page it searched goes away (tab or space switch). The marks stay on that
    /// page otherwise, so clear them on the page find was showing on.
    func dismissFind() {
        guard find != nil else { return }
        findPage?.clearFind()
        find = nil
    }
}
