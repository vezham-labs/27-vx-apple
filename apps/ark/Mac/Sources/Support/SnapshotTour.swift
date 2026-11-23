#if DEBUG
import AppKit
import SwiftUI
import BrowserCore
import BrowserEngine
import Suggest
import WebKit
import WebKitEngine

/// Debug only: with ARK_SNAPSHOT=<folder> set, walks through the main screens and saves a PNG of
/// the window at each step, then quits. For checking layouts on a Mac nobody is looking at.
@MainActor
struct SnapshotTour {
    let directory: URL
    let delegate: AppDelegate

    func run() async {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Wait for the first window, and say so (and quit) if it never comes, rather than hang.
        var waited = 0.0
        while delegate.browser == nil, waited < 20 { await pause(0.5); waited += 0.5 }
        await pause(2)
        guard let browser = delegate.browser else {
            note("no browser window after 20s; windows: \(NSApp.windows.map { $0.className })")
            NSApp.terminate(nil)
            return
        }
        note("tour started after \(waited)s")
        if let fixture = ProcessInfo.processInfo.environment["ARK_SNAPSHOT_FEATURE_URL"], let url = URL(string: fixture) {
            await featurePreviews(browser, base: url)
            NSApp.terminate(nil)
            return
        }
        let library = delegate.library
        // Fetch the favourites' icons first, so the shots show them rather than letters.
        for fav in browser.favorites {
            _ = try? await URLSession.shared.data(from: URL(string: "https://icons.duckduckgo.com/ip3/\(URLNormalizer.displayHost(fav.url)).ico")!)
        }
        save("1-launch")

        browser.newTab(url: URL(string: "https://www.apple.com")!)
        await pause(6)
        save("2-page")
        await savePage(browser, "2-page-content")

        browser.showCommandBar(.newTab)
        await pause(1)
        save("3-command-bar-empty")
        if let editor = window?.firstResponder as? NSTextView {
            editor.insertText("github", replacementRange: editor.selectedRange())
        }
        await pause(2)
        save("4-command-bar-github")
        browser.commandBar = nil

        browser.newTab(url: URL(string: "https://en.wikipedia.org/wiki/Arc_(web_browser)")!)
        await pause(5)
        browser.zoom(1)
        await pause(1)
        save("5-zoomed")
        browser.zoom(0)
        await pause(1)

        browser.toggleReader()
        await pause(3)
        note("reader showing: \(browser.isReaderShowing) title: \(browser.reader?.article.title ?? "-")")
        save("11-reader")
        if let page = browser.reader?.page { await saveImage(await page.snapshot(), "11-reader-content") }
        browser.zoom(1)
        await pause(1)
        if let page = browser.reader?.page { await saveImage(await page.snapshot(), "11-reader-larger") }
        browser.zoom(0)
        browser.closeReader()
        await pause(1)

        // A second window: its own space and tab, the first window's tabs untouched.
        let firstWindow = browser.nsWindow
        library.openWindow()
        await pause(3)
        let second = library.windows.first { $0 !== browser }
        note("windows: \(library.windows.count), second shows tab: \(second?.currentTab?.displayTitle ?? "none"), command bar: \(String(describing: second?.commandBar))")
        save("12-second-window", in: second?.nsWindow)
        if let second, let tab = browser.currentTab {
            // Moving the first window's tab over: the first window moves on to another tab.
            second.commandBar = nil
            browser.openInNewWindow(tab)
            await pause(3)
            note("after move: windows \(library.windows.count), first shows \(browser.currentTab?.displayTitle ?? "none")")
            save("12-tab-in-window", in: library.window(showing: tab)?.nsWindow)
        }
        for w in library.windows where w !== browser { w.nsWindow?.performClose(nil) }
        await pause(2)
        note("after closing: windows \(library.windows.count)")
        firstWindow?.makeKeyAndOrderFront(nil)
        await pause(1)

        withAnimation(Motion.spring) { browser.selectAdjacentSpace(1) }
        await pause(1)
        save("6-second-space")
        withAnimation(Motion.spring) { browser.selectAdjacentSpace(-1) }

        // The same screens in light mode.
        NSApp.appearance = NSAppearance(named: .aqua)
        await pause(1)
        save("9-light")
        browser.showCommandBar(.newTab)
        await pause(1)
        if let editor = window?.firstResponder as? NSTextView {
            editor.insertText("wiki", replacementRange: editor.selectedRange())
        }
        await pause(2)
        save("10-light-command-bar")
        browser.commandBar = nil
        NSApp.appearance = nil
        await pause(1)

        browser.toggleSidebar()
        await pause(1)
        save("7-sidebar-hidden")
        await savePage(browser, "7-page-content")
        withAnimation(Motion.peek) { browser.isSidebarPeeking = true }
        await pause(1)
        save("8-sidebar-peeking")
        browser.isSidebarPeeking = false
        browser.toggleSidebar()
        await pause(1)

        // Settings › Audio, light and dark, in a window of its own (SwiftUI's Settings scene can't be opened from here).
        UserDefaults.standard.set("audio", forKey: "settingsTab")
        let settings = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 460), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        settings.title = "Audio"
        settings.contentView = NSHostingView(rootView: SettingsView().environment(delegate.library).environment(delegate.updates))
        settings.center()
        settings.makeKeyAndOrderFront(nil)
        await pause(2)
        save("13-settings-audio-light", in: settings)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        await pause(1)
        save("14-settings-audio-dark", in: settings)
        settings.close()

        browser.saveNow()
        NSApp.terminate(nil)
    }

    private var window: NSWindow? {
        delegate.browser?.nsWindow ?? NSApp.windows.first { $0.isVisible && $0.contentView != nil && !($0 is NSPanel) }
    }

    private func featurePreviews(_ browser: Browser, base: URL) async {
        guard let window = browser.nsWindow else { note("missing window"); return }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        if ProcessInfo.processInfo.environment["ARK_MINI_PLAYER_PREVIEW"] == "1" {
            await miniPlayerPreview(browser, base: base)
            return
        }
        await namedProfileCheck()
        await spaceProfileCheck(browser)
        let first = base.appending(path: "atlas.html")
        let second = base.appending(path: "field-notes.html")
        browser.newTab(url: first)
        await pause(1)
        browser.newTab(url: second)
        await pause(1)
        saveVisible("sidebar-and-tabs", in: window)
        guard browser.lastUsedTab?.url == first else { note("last-used tab mismatch"); return }
        await commandPreview(browser, query: "last used tab", file: "last-used-tab")
        browser.run(command: "last-used-tab")
        guard browser.currentTab?.url == first else { note("last-used tab did not switch"); return }
        note("last-used tab switched")
        await splitPreview(browser, window: window, partnerURL: second)

        await commandPreview(browser, query: "full page image", file: "copy-full-page-image")
        browser.commandBar = nil
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        browser.copyFullPageImage(to: board)
        for _ in 0..<40 {
            if let png = board.data(forType: .png) {
                try? png.write(to: directory.appending(path: "full-page-image-output.png"))
                note("full-page PNG copied to preview pasteboard")
                break
            }
            await pause(0.15)
        }
        await regionPreview(browser, window: window)
        await elementPreview(browser, window: window)
        await recentTabsPreview(browser, window: window)
        await linkWindowPreview(browser, url: second)
        await pinFolderPreview(browser, window: window)
        await arcFolderImportCheck(browser, window: window, page: first)
        await liveFolderPreview(browser, window: window, sourcePage: base.appending(path: "live-source.html"))

        await commandPreview(browser, query: "export space links", file: "export-space-links")
        browser.commandBar = nil
        await pause(0.4)
        browser.exportSpaceLinks()
        await pause(0.7)
        if let panel = window.attachedSheet as? NSSavePanel {
            note("space export save dialog opened")
            panel.cancel(nil)
            await pause(0.4)
        }
        await commandPreview(browser, query: "import space links", file: "import-space-links")
        browser.commandBar = nil
        await pause(0.4)
        browser.importSpaceLinks()
        await pause(0.7)
        if let panel = window.attachedSheet as? NSOpenPanel {
            note("space import open dialog opened")
            panel.cancel(nil)
            await pause(0.4)
        }

        guard let host = browser.editableSiteStyleHost else { note("site style unavailable"); return }
        let css = "h1 { color: #a33df5; }\nmain { border-inline-start: 6px solid #a33df5; }"
        do { try browser.saveSiteStyle(css, for: host) }
        catch { note("site style could not save"); return }
        await pause(0.5)
        let world = "ark.preview"
        let check = "return getComputedStyle(document.querySelector('h1')).color;"
        if let color = try? await browser.currentController?.page.evaluate(check, inWorld: world) as? String {
            note("styled heading: \(color)")
        }
        browser.run(command: "edit-site-style")
        await pause(0.6)
        saveVisible("site-style-editor", in: window.attachedSheet ?? window)
        browser.siteStyleHost = nil
        await pause(0.6)
        browser.reload()
        await pause(1.5)
        if let color = try? await browser.currentController?.page.evaluate(check, inWorld: world) as? String {
            note("heading after reload: \(color)")
        }
        saveVisible("site-style-applied", in: window)

        if var otherHost = URLComponents(url: first, resolvingAgainstBaseURL: false) {
            otherHost.host = "localhost"
            if let url = otherHost.url {
                browser.newTab(url: url)
                await pause(1)
                if let color = try? await browser.currentController?.page.evaluate(check, inWorld: world) as? String {
                    note("heading on other host: \(color)")
                }
            }
        }

        browser.newTab(url: first, isPrivate: true)
        await pause(1)
        if let color = try? await browser.currentController?.page.evaluate(check, inWorld: world) as? String {
            note("heading in private tab: \(color)")
        }
        browser.closePrivateSpace()
        guard let atlas = browser.currentSpace.allTabs.first(where: { $0.url == first }) else { return }
        browser.select(atlas)
        await pause(0.5)
        do { try browser.saveSiteStyle("", for: host) }
        catch { note("site style could not clear") }
        await pause(0.5)
        if let color = try? await browser.currentController?.page.evaluate(check, inWorld: world) as? String {
            note("heading after clearing: \(color)")
        }
        await baselinePreviews(browser, window: window, atlas: atlas, otherPage: second)
        await settingsPreviews(browser, window: window)
    }

    private func miniPlayerPreview(_ browser: Browser, base: URL) async {
        let videoTab = browser.newTab(url: base.appending(path: "mini-player.html"))
        let page = browser.library.existingController(for: videoTab)?.page
        let fixtureState = try? await page?.evaluate("""
            const v = document.querySelector('video');
            if (!v) return JSON.stringify({ reason: 'no-video-element', ready: document.readyState,
                url: location.href, title: document.title, body: document.body?.innerText?.slice(0, 160) });
            const r = v.getBoundingClientRect();
            return JSON.stringify({ readyState: v.readyState, paused: v.paused, ended: v.ended,
                videoWidth: v.videoWidth, videoHeight: v.videoHeight, rect: [r.width, r.height],
                duration: v.duration, muted: v.muted, currentSrc: v.currentSrc });
            """, inWorld: "ark.preview") as? String
        note("mini-player fixture video: \(fixtureState ?? "unavailable")")
        var playingBefore = false
        for _ in 0..<60 {
            if let state = try? await page?.evaluate("""
                const v = document.querySelector('video');
                return !!v && v.readyState >= 2 && !v.paused;
                """, inWorld: "ark.preview") as? Bool, state {
                playingBefore = true
                break
            }
            await pause(0.25)
        }
        guard playingBefore else { note("mini-player fixture did not start playback"); return }

        let playingState = try? await page?.evaluate("""
            const v = document.querySelector('video');
            if (!v) return 'no-video-element';
            const r = v.getBoundingClientRect();
            return JSON.stringify({ readyState: v.readyState, paused: v.paused, ended: v.ended,
                videoWidth: v.videoWidth, videoHeight: v.videoHeight, rect: [r.width, r.height],
                duration: v.duration, muted: v.muted, currentSrc: v.currentSrc });
            """, inWorld: "ark.preview") as? String
        note("mini-player playing fixture state: \(playingState ?? "unavailable")")

        note("mini-player fixture selected as current tab: \(browser.currentTab?.id == videoTab.id)")
        browser.run(command: "mini-player")
        for _ in 0..<80 where !browser.library.videoMiniPlayer.isShowing { await pause(0.1) }
        let opened = browser.library.videoMiniPlayer.isShowing
        guard opened else {
            note("mini-player command did not open the panel; toast: \(browser.toast ?? "none"); \(browser.library.videoMiniPlayer.previewFailure ?? "no diagnostic")")
            return
        }
        guard browser.library.videoMiniPlayer.isShowing,
              let panel = browser.library.videoMiniPlayer.previewWindow else {
            note("mini-player command did not open its floating panel; toast: \(browser.toast ?? "none")")
            return
        }
        browser.library.videoMiniPlayer.revealControlsForPreview()
        await pause(5.1)
        // Capture the native panel view tree directly. Avoid WindowServer screen
        // recording permission prompts in this local-only fixture.
        save("mini-player", in: panel)
        await saveImage(await page?.snapshot(), "mini-player-page")
        let floating = try? await page?.evaluate("""
            const v = document.querySelector('video');
            return !!v && document.documentElement.classList.contains('office-floating') && !v.paused;
            """, inWorld: "ark.preview") as? Bool
        let frameState = try? await page?.evaluate("""
            const v = document.querySelector('video');
            if (!v) return 'no-video-element';
            const c = document.createElement('canvas'); c.width = 16; c.height = 9;
            const x = c.getContext('2d'); x.drawImage(v, 0, 0, c.width, c.height);
            const p = x.getImageData(0, 0, c.width, c.height).data;
            const avg = [0, 0, 0];
            for (let i = 0; i < p.length; i += 4) for (let j = 0; j < 3; j++) avg[j] += p[i + j];
            return JSON.stringify({ averageRGB: avg.map(n => Math.round(n / (p.length / 4))),
                visibility: getComputedStyle(v).visibility, opacity: getComputedStyle(v).opacity,
                dimensions: [v.videoWidth, v.videoHeight], currentTime: v.currentTime });
            """, inWorld: "ark.preview") as? String
        note("mini-player rendered frame: \(frameState ?? "unavailable")")

        let otherTab = browser.newTab(url: base.appending(path: "field-notes.html"))
        await pause(0.3)
        browser.select(videoTab)
        var returned = false
        for _ in 0..<40 {
            returned = (try? await page?.evaluate("""
                const v = document.querySelector('video');
                return !!v && !document.documentElement.classList.contains('office-floating') && !v.paused;
                """, inWorld: "ark.preview") as? Bool) == true
            if returned { break }
            await pause(0.1)
        }
        note("mini-player opens playing video: \(floating == true); selecting its tab restores inline playback: \(returned == true)")
        browser.close(otherTab)
    }

    private func namedProfileCheck() async {
        let first = UUID()
        let second = UUID()
        await checkNamedStores(first, second)
        for id in [first, second] {
            try? await WKWebsiteDataStore.remove(forIdentifier: id)
        }
    }

    private func checkNamedStores(_ first: UUID, _ second: UUID) async {
        let engine = WebKitEngine()
        let delegate = ProfileCheckDelegate()
        func store(_ profile: BrowsingProfile) -> WKWebsiteDataStore? {
            let page = engine.makePage(options: PageOptions(profile: profile), delegate: delegate)
            defer { page.close() }
            return (page.view as? WKWebView)?.configuration.websiteDataStore
        }
        guard let writer = store(.named(first)), let reader = store(.named(first)),
              let other = store(.named(second)), let standard = store(.standard),
              let ephemeral = store(.ephemeral),
              let cookie = HTTPCookie(properties: [
                .domain: "profile-fixture.invalid", .path: "/", .name: first.uuidString,
                .value: "isolated", .expires: Date.now.addingTimeInterval(600),
              ]) else {
            note("named profile fixture could not create its stores")
            return
        }
        await writer.httpCookieStore.setCookie(cookie)
        func hasFixtureCookie(_ store: WKWebsiteDataStore) async -> Bool {
            await store.httpCookieStore.allCookies().contains { $0.name == cookie.name && $0.value == cookie.value }
        }
        let sameProfile = await hasFixtureCookie(reader)
        let differentProfile = await hasFixtureCookie(other)
        let defaultProfile = await hasFixtureCookie(standard)
        let privateProfile = await hasFixtureCookie(ephemeral)
        note("named store shares cookies only within the same profile: \(sameProfile && !differentProfile && !defaultProfile && !privateProfile)")
        await engine.clearWebsiteData(for: .named(first))
        let cleared = await hasFixtureCookie(reader) == false
        note("named profile website data cleared: \(cleared)")
    }

    private final class ProfileCheckDelegate: EnginePageDelegate {}

    private func spaceProfileCheck(_ browser: Browser) async {
        let library = browser.library
        guard let profile = WebsiteProfile(name: "Research") else { return }
        library.settings.websiteProfiles.append(profile)
        await verifySpaceAssignments(browser, profile: profile)
        library.settings.websiteProfiles.removeAll { $0.id == profile.id }
        try? await WKWebsiteDataStore.remove(forIdentifier: profile.id)
    }

    private func verifySpaceAssignments(_ browser: Browser, profile: WebsiteProfile) async {
        let library = browser.library
        let source = library.addSpace()
        let shared = library.addSpace()
        let standard = library.addSpace()
        source.name = "Projects"
        shared.name = "Reference"
        standard.name = "Reading"
        defer {
            library.deleteSpace(source)
            library.deleteSpace(shared)
            library.deleteSpace(standard)
        }
        let tab = library.insertTab(url: nil, in: source, for: browser)
        let original = library.controller(for: tab)
        library.assignWebsiteProfile(profile.id, to: source)
        library.assignWebsiteProfile(profile.id, to: shared)
        let named = library.controller(for: tab)
        func uses(_ controller: TabController, profileID: UUID?) -> Bool {
            guard let store = (controller.page.view as? WKWebView)?.configuration.websiteDataStore else { return false }
            return store.isPersistent && store.identifier == profileID
        }
        let assigned = named !== original && uses(named, profileID: profile.id)
        library.move(tab, to: shared)
        let keptPage = library.controller(for: tab) === named
        tab.interactionState = Data([1])
        tab.websiteSessionProfileID = profile.id
        library.move(tab, to: standard)
        let reset = tab.interactionState == nil && tab.websiteSessionProfileID == nil
        let rebuilt = library.controller(for: tab)
        note("space profile assignment rebuilt the page for its named store: \(assigned)")
        note("moving tabs kept the same-profile page and reset cross-profile state: \(keptPage && reset && rebuilt !== named && uses(rebuilt, profileID: nil))")
        let defaults = UserDefaults.standard
        let previousPane = defaults.object(forKey: "settingsTab")
        defer { defaults.set(previousPane, forKey: "settingsTab") }
        defaults.set("spaces", forKey: "settingsTab")
        let settings = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 330),
                                styleMask: [.titled, .closable], backing: .buffered, defer: false)
        settings.title = "Spaces"
        settings.contentView = NSHostingView(rootView: SettingsView().environment(library).environment(delegate.updates))
        settings.center()
        settings.makeKeyAndOrderFront(nil)
        await pause(0.8)
        saveVisible("space-profiles", in: settings)
        settings.close()
        browser.nsWindow?.makeKeyAndOrderFront(nil)
    }

    private func arcFolderImportCheck(_ browser: Browser, window: NSWindow, page: URL) async {
        let data = Data("""
        {"sidebar":{"containers":[{"spaces":[{
            "id":"coast","title":"Coastal Survey",
            "newContainerIDs":[{"pinned":{}},"pins"],"containerIDs":["pinned","legacy","unpinned","today"]
        }],"items":[
            {"id":"pins","childrenIds":["root","folder","root"]},
            {"id":"folder","title":"Research","data":{"list":{}},"childrenIds":["work","child","folder"]},
            {"id":"child","title":"References","data":{"list":{}},"childrenIds":["nested"]},
            {"id":"today","childrenIds":["open","local"]},
            {"id":"root","data":{"tab":{"savedTitle":"Root","savedURL":"https://example.test/root"}}},
            {"id":"work","title":"Research plan","data":{"tab":{"savedURL":"https://example.test/work"}}},
            {"id":"nested","data":{"tab":{"savedTitle":"Reference","savedURL":"\(page.absoluteString)"}}},
            {"id":"open","data":{"tab":{"savedTitle":"Today","savedURL":"https://example.test/today"}}},
            {"id":"local","data":{"tab":{"savedTitle":"Local","savedURL":"file:///tmp/page"}}}
        ]}]}}
        """.utf8)
        let imported = BrowserImport.arcSidebar(data)
        guard let source = imported.spaces.first else {
            note("Arc folder import fixture found no Space")
            return
        }
        let former = browser.currentSpace
        let formerTab = browser.currentTab
        let space = browser.library.addSpace()
        space.name = source.name
        defer {
            browser.selectSpace(former)
            if let formerTab { browser.select(formerTab) }
            browser.library.deleteSpace(space)
        }
        source.populate(space)
        let names = space.pinFolders.map { space.pinFolderName($0) }
        let expected = names == ["Research", "Research / References"]
            && space.pinned.map(\.displayTitle) == ["Root", "Research plan", "Reference"]
            && space.rootPins.map(\.displayTitle) == ["Root"]
            && space.pinned.last?.pinFolderID == space.pinFolders.last?.id
            && space.today.map(\.displayTitle) == ["Today"]
        note("Arc folder import fixture matched folder hierarchy, pin order, and open tabs: \(expected)")
        if expected, let reference = space.pinned.last {
            browser.select(reference)
            await pause(1.3)
            saveVisible("arc-folder-import", in: window)
        }
    }

    private func liveFolderPreview(_ browser: Browser, window: NSWindow, sourcePage: URL) async {
        let space = browser.currentSpace
        do {
            guard let folder = try await space.addLiveFolder(address: sourcePage.absoluteString),
                  let feed = folder.feed, feed.source.lastPathComponent == "field-feed.xml",
                  feed.articles.map(\.title) == ["Atlas", "Field Notes"] else {
                note("live folder failed to discover the fixture feed")
                return
            }
            defer { space.removePinFolder(folder.id) }
            let changed = try await space.refreshLiveFolder(folder.id)
            let refreshed = space.pinFolders.first { $0.id == folder.id }?.feed
            let expected = changed && refreshed?.articles.map(\.title) == ["Atlas revised", "Field Notes"]
                && refreshed?.articles.map(\.id) == feed.articles.map(\.id)
            note("live folder discovered and refreshed with stable article IDs: \(expected)")
            guard expected else { return }
            await pause(0.6)
            saveVisible("live-folder", in: window)
            let failed: Bool
            do {
                _ = try await space.refreshLiveFolder(folder.id)
                failed = false
            } catch {
                failed = true
            }
            note("live folder kept cached data after request failed: \(failed && space.pinFolders.first { $0.id == folder.id }?.feed == refreshed)")
            if let archive = SpaceLinkArchive(space: space) {
                let imported = try SpaceLinkArchive(data: archive.encoded()).makeSpace(colorIndex: space.colorIndex)
                if let importedFolder = imported.pinFolders.first(where: { $0.feed?.source == feed.source }) {
                    let ignored = try await imported.refreshLiveFolder(importedFolder.id, allowActivation: false)
                    let wasPaused = !ignored && importedFolder.feed?.articles.isEmpty == true
                    let resumed = try await imported.refreshLiveFolder(importedFolder.id)
                    note("imported live folder fetched only after resume: \(wasPaused && resumed && imported.pinFolders.first { $0.id == importedFolder.id }?.feed == refreshed)")
                }
            }
        } catch {
            note("live folder fixture error: \(error.localizedDescription)")
        }
    }

    private func pinFolderPreview(_ browser: Browser, window: NSWindow) async {
        let space = browser.currentSpace
        guard let tab = browser.currentTab, !tab.isPinned,
              let folder = space.addPinFolder(named: "Coastal Survey"),
              let child = space.addPinFolder(named: "Reference Pages", inside: folder.id) else { return }
        defer {
            space.removePinFolder(child.id)
            space.removePinFolder(folder.id)
            if tab.isPinned { browser.togglePinned(tab) }
        }
        await pause(0.8)
        let nested = await drag(tab, into: child.id, in: space, browser: browser)
        note("drag from Today into nested pin folder: \(nested)")
        guard nested else { return }
        saveVisible("pinned-folders", in: window)
        let moved = await drag(tab, into: folder.id, in: space, browser: browser)
        let returned = moved ? await drag(tab, into: child.id, in: space, browser: browser) : false
        note("drag a pin between folders in both directions: \(moved && returned)")
        space.togglePinFolder(folder.id)
        if space.pinFolders.contains(where: { $0.id == folder.id && $0.isCollapsed }),
           space.selectedTabID == tab.id, space.rootPins.allSatisfy({ $0.id != tab.id }) {
            note("collapse kept the nested pin selected without adding it to the root")
        }
    }

    private func drag(_ tab: BrowserTab, into folderID: UUID, in space: Space, browser: Browser) async -> Bool {
        guard let dragging = browser.sidebarDragging, let row = dragging.rowFrames[tab.id],
              let heading = dragging.folderFrames[folderID] else { return false }
        let source = CGPoint(x: row.midX, y: row.midY)
        let destination = CGPoint(x: heading.midX, y: heading.midY)
        dragging.changed(tab, from: source, to: source, in: space, browser: browser)
        await pause(0.2)
        dragging.changed(tab, from: source, to: destination, in: space, browser: browser)
        let targeted = dragging.target?.folderID == folderID
        dragging.ended(tab, in: space, browser: browser)
        await pause(0.8)
        return targeted && !dragging.isLifted(tab.id) && tab.isPinned && tab.pinFolderID == folderID
            && !space.today.contains { $0.id == tab.id } && browser.currentTab === tab
    }

    private func linkWindowPreview(_ browser: Browser, url: URL) async {
        let library = browser.library
        guard let firstTab = browser.currentTab else { return }
        let destination = library.regularSpaces.first { $0.id != browser.currentSpace.id }
        let originalDestination = library.settings.externalLinksSpaceID
        library.settings.externalLinksSpaceID = destination?.id
        defer { library.settings.externalLinksSpaceID = originalDestination }
        library.openExternal(url, inLinkWindow: true)
        guard let preview = library.linkWindows.values.first, let window = preview.window else {
            note("link preview window missing")
            return
        }
        defer {
            if library.space(containing: preview.tab) != nil { browser.close(preview.tab) }
            library.linkWindows[preview.tab.id]?.close()
            browser.select(firstTab)
        }
        for _ in 0..<25 {
            if preview.tab.url == url, !preview.tab.title.isEmpty, !preview.tab.isLoading { break }
            await pause(0.15)
        }
        guard preview.tab.url == url, library.space(containing: preview.tab) == nil, browser.currentTab === firstTab else {
            note("link preview changed the browser before handoff")
            return
        }
        saveVisible("link-preview-window", in: window)
        let original = preview.controller.page
        preview.keep()
        await pause(0.5)
        if browser.currentTab === preview.tab, browser.currentController?.page === original,
           library.linkWindows[preview.tab.id] == nil, destination == nil || browser.currentSpace === destination {
            note("link preview kept its live page when promoted to a tab")
        } else {
            note("link preview did not preserve its page or destination on handoff")
        }
        let disposable = library.showLinkPreview(url)
        disposable.close()
        if library.linkWindows[disposable.tab.id] == nil, library.space(containing: disposable.tab) == nil {
            note("closing a link preview left no tab in the library")
        }
    }

    private func recentTabsPreview(_ browser: Browser, window: NSWindow) async {
        guard let active = browser.currentTab, let previous = browser.lastUsedTab else {
            note("recent tabs fixture is missing its active or previous tab")
            return
        }
        let dormant = browser.newTab(url: nil, select: false)
        dormant.title = "Survey Checklist"
        defer {
            browser.isRecentTabsPresented = false
            browser.close(dormant)
            browser.select(active)
        }
        guard browser.recentTabs.prefix(2).map(\.id) == [active.id, previous.id] else {
            note("recent tabs order did not match active and previously used tabs")
            return
        }
        browser.toast = nil
        browser.run(command: ShortcutAction.recentTabs.rawValue)
        await pause(1.4)
        guard let sheet = window.attachedSheet else {
            note("recent tabs sheet missing")
            return
        }
        saveVisible("recent-tabs", in: sheet)
        if browser.library.existingController(for: dormant) == nil {
            note("recent tabs picker left dormant tab unloaded")
        }
        if let down = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                      timestamp: 0, windowNumber: sheet.windowNumber, context: nil,
                                      characters: "\u{F701}", charactersIgnoringModifiers: "\u{F701}",
                                      isARepeat: false, keyCode: 125) {
            NSApp.sendEvent(down)
            await pause(0.2)
        }
        if let enter = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                       timestamp: 0, windowNumber: sheet.windowNumber, context: nil,
                                       characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36) {
            NSApp.sendEvent(enter)
        }
        await pause(0.5)
        if browser.currentTab === dormant, window.attachedSheet == nil {
            note("recent tabs picker selected the next result with Down and Return")
        } else {
            note("recent tabs keyboard selected \(browser.currentTab?.displayTitle ?? "no tab")")
        }
    }

    private func regionPreview(_ browser: Browser, window: NSWindow) async {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        guard let picker = browser.selectPageArea(to: board) else {
            note("area picker missing")
            return
        }
        guard window.firstResponder === picker else {
            note("area picker did not receive focus")
            picker.cancelOperation(nil)
            return
        }
        let start = NSPoint(x: max(36, (picker.bounds.width - 860) / 2 + 36), y: 230)
        let end = NSPoint(x: start.x + 300, y: start.y + 180)
        guard let down = captureMouseEvent(.leftMouseDown, at: start, in: picker, window: window),
              let drag = captureMouseEvent(.leftMouseDragged, at: end, in: picker, window: window),
              let up = captureMouseEvent(.leftMouseUp, at: end, in: picker, window: window) else { return }
        NSApp.sendEvent(down)
        NSApp.sendEvent(drag)
        await pause(0.5)
        saveVisible("copy-page-area", in: window)
        NSApp.sendEvent(up)
        for _ in 0..<40 {
            if let png = board.data(forType: .png), let bitmap = NSBitmapImageRep(data: png) {
                note("page area: \(bitmap.pixelsWide)×\(bitmap.pixelsHigh) pixels")
                try? png.write(to: directory.appending(path: "page-area-output.png"))
                break
            }
            await pause(0.15)
        }
        let changeCount = board.changeCount
        if let cancel = browser.selectPageArea(to: board) {
            cancel.cancelOperation(nil)
            if cancel.superview == nil, board.changeCount == changeCount { note("area picker cancelled without copying") }
        }
    }

    private func elementPreview(_ browser: Browser, window: NSWindow) async {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        guard let element = try? await browser.currentController?.page.evaluate("""
            const rect = document.querySelector("h2").getBoundingClientRect();
            return [rect.x + 32, rect.y + rect.height / 2, rect.width, rect.height];
            """, inWorld: "Ark Capture Fixture") as? [NSNumber], element.count == 4,
              let picker = browser.selectPageElement(to: board) else {
            note("element fixture could not start")
            return
        }
        await pause(0.35)
        saveVisible("copy-page-element", in: window)
        let point = NSPoint(x: element[0].doubleValue, y: element[1].doubleValue)
        guard let down = captureMouseEvent(.leftMouseDown, at: point, in: picker, window: window),
              let up = captureMouseEvent(.leftMouseUp, at: point, in: picker, window: window) else { return }
        NSApp.sendEvent(down)
        NSApp.sendEvent(up)
        for _ in 0..<40 {
            if let png = board.data(forType: .png), let bitmap = NSBitmapImageRep(data: png) {
                let scale = window.backingScaleFactor
                let matches = abs(Double(bitmap.pixelsWide) / scale - element[2].doubleValue) <= 2
                    && abs(Double(bitmap.pixelsHigh) / scale - element[3].doubleValue) <= 2
                note("page element: \(bitmap.pixelsWide)×\(bitmap.pixelsHigh) pixels, bounds match: \(matches)")
                if matches { try? png.write(to: directory.appending(path: "page-element-output.png")) }
                return
            }
            await pause(0.15)
        }
        note("element fixture did not copy a PNG")
    }

    private func captureMouseEvent(_ type: NSEvent.EventType, at point: NSPoint,
                                   in picker: NSView, window: NSWindow) -> NSEvent? {
        NSEvent.mouseEvent(with: type, location: picker.convert(point, to: nil),
                           modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                           context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
    }

    private func settingsPreviews(_ browser: Browser, window: NSWindow) async {
        let defaults = UserDefaults.standard
        let previousPane = defaults.object(forKey: "settingsTab")
        defer { defaults.set(previousPane, forKey: "settingsTab") }
        browser.settings.blockContent = true
        SpaceRouter.shared.isEnabled = true
        for (pane, file) in [("spaces", "shared-collections"), ("routing", "space-routing"), ("shortcuts", "custom-shortcuts"), ("privacy", "ad-blocker")] {
            browser.library.openSettings(pane: pane)
            await pause(0.8)
            guard let settings = NSApp.keyWindow, settings !== window else {
                note("settings window missing for \(pane)")
                continue
            }
            saveVisible(file, in: settings)
        }
    }

    private func splitPreview(_ browser: Browser, window: NSWindow, partnerURL: URL) async {
        guard let first = browser.currentTab, let second = browser.splitCandidates.first(where: { $0.url == partnerURL }) else {
            note("split candidates missing")
            return
        }
        browser.splitWith(second)
        await pause(1)
        guard browser.visibleTabIDs == [first.id, second.id],
              browser.library.window(showing: second) === browser,
              browser.library.existingController(for: first)?.page.view.window === window,
              browser.library.existingController(for: second)?.page.view.window === window else {
            note("split did not mount both panes")
            browser.separateSplit()
            return
        }
        if let secondView = browser.library.existingController(for: second)?.page.view,
           let click = NSEvent.mouseEvent(with: .leftMouseDown,
                                          location: secondView.convert(NSPoint(x: 30, y: 30), to: nil),
                                          modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                          context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
            PageHost.focusClickedPane(click)
        }
        browser.resizeSplit(to: 0.58)
        guard browser.currentTab === second, browser.activeSplit?.focused == second.id else {
            note("split pane did not receive focus")
            browser.separateSplit()
            browser.select(first)
            return
        }
        await saveSplitPreview("split-view", browser: browser, window: window, first: first, second: second)
        browser.setSplitAxis(.stacked)
        await saveSplitPreview("split-view-stacked", browser: browser, window: window, first: first, second: second)
        if let data = try? JSONEncoder().encode(browser.splitBySpace),
           (try? JSONDecoder().decode([UUID: TabSplit].self, from: data)) == browser.splitBySpace {
            note("split width, axis, membership, and focus round-tripped")
        }
        let oldActivity = first.lastActive
        first.lastActive = .distantPast
        browser.library.archiveStaleTabs()
        if browser.visibleTabIDs.contains(first.id) { note("unfocused pane protected from archive") }
        first.lastActive = oldActivity
        let partner = browser.newTab(url: partnerURL, in: browser.currentSpace, select: false)
        await pause(0.7)
        browser.select(partner)
        if browser.activeSplit == nil, browser.visibleTabIDs == [partner.id] {
            browser.select(second)
            if browser.visibleTabIDs == [first.id, second.id] { note("selecting a split tab reopened its pair") }
        }
        browser.splitWith(partner)
        browser.focusSplitPane(partner)
        browser.close(partner)
        if browser.activeSplit == nil, browser.currentTab === second { note("closing a split pane kept its partner") }
        browser.select(first)
    }

    private func saveSplitPreview(_ name: String, browser: Browser, window: NSWindow,
                                  first: BrowserTab, second: BrowserTab) async {
        await pause(0.8)
        for tab in [first, second] {
            if let page = browser.library.existingController(for: tab)?.page, let image = await page.snapshot() {
                note("\(name), \(tab.displayTitle): \(image.width)×\(image.height) viewport")
            }
        }
        window.displayIfNeeded()
        await pause(0.5)
        saveVisible(name, in: window)
    }

    private func baselinePreviews(_ browser: Browser, window: NSWindow, atlas: BrowserTab, otherPage: URL) async {
        browser.togglePinned(atlas)
        await pause(0.7)
        saveVisible("pinned-tab", in: window)
        browser.openGlance(otherPage, profile: .standard)
        await pause(1)
        saveVisible("glance-link-preview", in: window)
        browser.closeGlance()
        await pause(0.4)
        let stale = browser.newTab(url: otherPage, select: false)
        stale.title = "Survey Checklist"
        stale.lastActive = .now.addingTimeInterval(-(browser.settings.archiveAfterHours + 24) * 3_600)
        browser.library.archiveStaleTabs()
        guard browser.archive.contains(where: { $0.id == stale.id }) else { note("fixture tab was not archived"); return }
        browser.isArchivePresented = true
        await pause(0.7)
        saveVisible("auto-archive", in: window.attachedSheet ?? window)
        browser.isArchivePresented = false
        await pause(0.7)
        browser.openLibrary()
        await pause(0.7)
        saveVisible("extension-library", in: window)
    }

    private func commandPreview(_ browser: Browser, query: String, file: String) async {
        browser.commandBar = nil
        await pause(0.4)
        browser.showCommandBar(.commands)
        await pause(0.5)
        if let editor = browser.nsWindow?.firstResponder as? NSTextView {
            editor.insertText(query, replacementRange: NSRange(location: 0, length: (editor.string as NSString).length))
        }
        await pause(0.45)
        if let window = browser.nsWindow { saveVisible(file, in: window) }
    }

    private func saveVisible(_ name: String, in window: NSWindow) {
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        let target = directory.appending(path: "\(name).png")
        capture.arguments = ["-x", "-o", "-l", String(window.windowNumber), target.path]
        if (try? capture.run()) != nil {
            capture.waitUntilExit()
            if capture.terminationStatus == 0 { return }
        }
        save(name, in: window)
    }

    /// A line in report.txt, for things a picture can't show.
    private func note(_ line: String) {
        let url = directory.appending(path: "report.txt")
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }

    private func pause(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    /// The window's views drawn into a bitmap. Web content may come out blank this way.
    private func save(_ name: String, in target: NSWindow? = nil) {
        let window = target ?? self.window
        guard let view = window?.contentView?.superview ?? window?.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: directory.appending(path: "\(name).png"))
    }

    /// The page itself, from the engine, since window captures can miss it.
    private func savePage(_ browser: Browser, _ name: String) async {
        await saveImage(await browser.currentController?.page.snapshot(), name)
    }

    private func saveImage(_ image: CGImage?, _ name: String) async {
        guard let image else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        try? rep.representation(using: .png, properties: [:])?.write(to: directory.appending(path: "\(name).png"))
    }
}
#endif
