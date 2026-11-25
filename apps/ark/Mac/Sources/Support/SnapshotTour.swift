#if DEBUG
import AppKit
import SwiftUI
import BrowserCore
import BrowserEngine
import Extensibility
import Suggest
import WebKit
import WebKitEngine

@MainActor
private enum SnapshotTourWindows {
    static var retained: [NSWindow] = []
}

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
        if ProcessInfo.processInfo.environment["ARK_SETTINGS_PREVIEW_ONLY"] == "1" {
            await settingsPreviews(browser, window: browser.nsWindow!)
            NSApp.terminate(nil)
            return
        }
        if let fixture = ProcessInfo.processInfo.environment["ARK_SNAPSHOT_FEATURE_URL"], let url = URL(string: fixture) {
            await featurePreviews(browser, base: url)
            note("feature preview branch returned")
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

        await verifySleepingInnerScroll(browser, library: library)
        browser.saveNow()
        NSApp.terminate(nil)
    }

    private func verifySleepingInnerScroll(_ browser: Browser, library: Library) async {
        let fixture = directory.appending(path: "nested-scroll-fixture.html")
        let content = """
        <!doctype html><meta charset="utf-8"><title>Nested scroll fixture</title>
        <style>body{font:16px sans-serif}#feed{height:600px;width:800px;overflow:auto;border:1px solid}
        #items{height:5000px;background:repeating-linear-gradient(#fff 0 39px,#ddd 40px)}</style>
        <div id="feed"><div id="items">Nested scroll restoration fixture</div></div>
        """
        do { try content.write(to: fixture, atomically: true, encoding: .utf8) }
        catch { note("nested scroll fixture write failed: \(error)"); return }
        guard let url = URL(string: fixture.absoluteString + "?target") else { return }
        let space = browser.currentSpace
        let target = library.insertTab(url: url, in: space, for: browser)
        browser.select(target)
        for _ in 0..<40 {
            if let page = library.existingController(for: target)?.page, !page.state.isLoading,
               page.state.url == url { break }
            await pause(0.1)
        }
        guard let page = library.existingController(for: target)?.page else {
            note("nested scroll fixture target has no page")
            return
        }
        let positioned = try? await page.evaluate("return (() => { const feed = document.querySelector('#feed'); if (!feed) return 'missing'; feed.scrollTop = 1200; return String(feed.scrollTop); })()", inWorld: "page") as? String
        guard positioned == "1200" else {
            note("nested scroll fixture failed to position target page: url=\(String(describing: page.state.url)) loading=\(page.state.isLoading) result=\(String(describing: positioned))")
            return
        }
        await library.unloadForDebugCheck(target.id)
        let didUnload = library.existingController(for: target) == nil
        guard didUnload else { note("nested scroll fixture did not evict its target page"); return }
        browser.select(target)
        for _ in 0..<80 {
            if let page = library.existingController(for: target)?.page, !page.state.isLoading,
               page.state.url == url { break }
            await pause(0.1)
        }
        await pause(2)
        let restored = try? await library.existingController(for: target)?.page.evaluate("return (() => { const feed = document.querySelector('#feed'); return feed ? String(feed.scrollTop) : 'missing'; })()", inWorld: "page") as? String
        note("nested scroll after sleeping-page restore: \(restored ?? "missing") (expected 1200)")
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
        if ProcessInfo.processInfo.environment["ARK_PIP_FRAME_CHECK_ONLY"] == "1" {
            await pictureInPictureFrameCheck(browser, base: base)
            return
        }
        if ProcessInfo.processInfo.environment["ARK_PIN_FOLDER_CHECK_ONLY"] == "1" {
            browser.newTab(url: base.appending(path: "field-notes.html"))
            await pause(0.8)
            await pinFolderPreview(browser, window: window, base: base)
            return
        }
        let first = base.appending(path: "atlas.html")
        let second = base.appending(path: "field-notes.html")
        if ProcessInfo.processInfo.environment["ARK_GLANCE_BOOST_CHECK_ONLY"] == "1" {
            browser.newTab(url: first)
            await pause(1)
            guard let host = SiteStyles.host(of: first) else { note("Glance Boost fixture has no host"); return }
            do {
                try browser.saveSiteStyle("body { background-color: rgb(12, 34, 56) !important; }", for: host)
                browser.openGlance(second, profile: .standard)
                await pause(2)
                let page = browser.glance?.page
                let initial = try await page?.evaluate("return getComputedStyle(document.body).backgroundColor", inWorld: "Ark Glance Audit") as? String
                try browser.saveSiteStyle("body { background-color: rgb(65, 43, 21) !important; }", for: host)
                await pause(0.5)
                let updated = try await page?.evaluate("return getComputedStyle(document.body).backgroundColor", inWorld: "Ark Glance Audit") as? String
                note("Glance Boost after load and update: \(initial == "rgb(12, 34, 56)" && updated == "rgb(65, 43, 21)") (initial: \(initial ?? "nil"), updated: \(updated ?? "nil"))")
                page?.load(first)
                await pause(2)
                let navigated = try await page?.evaluate("return getComputedStyle(document.body).backgroundColor", inWorld: "Ark Glance Audit") as? String
                note("Glance Boost after navigation: \(navigated == "rgb(65, 43, 21)") (\(navigated ?? "nil"))")
                browser.library.openWindow()
                await pause(1)
                if let other = browser.library.windows.first(where: { $0 !== browser }) {
                    other.openGlance(second, profile: .standard)
                    await pause(2)
                    try browser.saveSiteStyle("body { background-color: rgb(21, 43, 65) !important; }", for: host)
                    await pause(0.5)
                    let otherColor = try await other.glance?.page.evaluate("return getComputedStyle(document.body).backgroundColor", inWorld: "Ark Glance Audit") as? String
                    note("Glance Boost update across windows: \(otherColor == "rgb(21, 43, 65)") (\(otherColor ?? "nil"))")
                    other.closeGlance()
                    other.nsWindow?.performClose(nil)
                } else { note("Glance Boost cross-window fixture could not open a window") }
                if host == "127.0.0.1", var otherHost = URLComponents(url: first, resolvingAgainstBaseURL: false) {
                    otherHost.host = "localhost"
                    if let url = otherHost.url {
                        page?.load(url)
                        await pause(2)
                        let otherColor = try await page?.evaluate("return getComputedStyle(document.body).backgroundColor", inWorld: "Ark Glance Audit") as? String
                        note("Glance excludes unrelated host Boost: \(browser.glance?.loadedURL?.host() == "localhost" && otherColor != nil && otherColor != "rgb(21, 43, 65)") (\(otherColor ?? "nil"))")
                    }
                }
                browser.closeGlance()
                browser.openGlance(second, profile: .ephemeral)
                await pause(2)
                let privateColor = try await browser.glance?.page.evaluate("return getComputedStyle(document.body).backgroundColor", inWorld: "Ark Glance Audit") as? String
                note("Private Glance excludes Boost: \(privateColor != nil && privateColor != "rgb(21, 43, 65)") (\(privateColor ?? "nil"))")
                browser.closeGlance()
                let agentTab = browser.library.insertTab(url: first, in: browser.library.agents.agentSpace, source: .link, for: browser)
                browser.openGlance(second, profile: .standard, source: agentTab)
                await pause(2)
                try browser.saveSiteStyle("body { background-color: rgb(45, 67, 89) !important; }", for: host)
                await pause(0.5)
                let agentColor = try await browser.glance?.page.evaluate("return getComputedStyle(document.body).backgroundColor", inWorld: "Ark Glance Audit") as? String
                note("Agent-origin Glance excludes Boost after update: \(agentColor != nil && agentColor != "rgb(45, 67, 89)") (\(agentColor ?? "nil"))")
                browser.closeGlance()
                try browser.library.siteStyles.set("", for: host)
            } catch { note("Glance Boost check failed: \(error)") }
            return
        }
        if ProcessInfo.processInfo.environment["ARK_EASEL_CHECK_ONLY"] == "1" {
            browser.newTab(url: first)
            await pause(1)
            await easelPreview(browser, window: window, page: first)
            return
        }
        if ProcessInfo.processInfo.environment["ARK_PIN_LINK_CHECK_ONLY"] == "1" {
            browser.newTab(url: second)
            await pause(1)
            await pinnedLinkNavigationCheck(browser, sourceURL: second, targetURL: first)
            await pinnedCloseNavigationCheck(browser, sourceURL: second, previousURL: first)
            return
        }
        await namedProfileCheck()
        note("named profile check returned")
        await spaceProfileCheck(browser)
        note("Space profile check returned; active Space: \(browser.currentSpace.name), current tab: \(browser.currentTab?.displayTitle ?? "none")")
        note("opening first local fixture page")
        browser.newTab(url: first)
        await pause(1)
        note("first local fixture page loaded: \(browser.currentTab?.url?.absoluteString ?? "none")")
        browser.newTab(url: second)
        await pause(1)
        note("second local fixture page loaded: \(browser.currentTab?.url?.absoluteString ?? "none")")
        saveVisible("sidebar-and-tabs", in: window)
        let previousTabURL = browser.lastUsedTab?.url
        note("last-used tab before pinned-link check: \(previousTabURL?.absoluteString ?? "none")")
        guard previousTabURL == first else { note("last-used tab mismatch"); return }
        await pinnedLinkNavigationCheck(browser, sourceURL: second, targetURL: first)
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
        await pinFolderPreview(browser, window: window, base: base)
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
        do { try browser.saveSiteStyle(css, font: .serif, for: host) }
        catch { note("site style could not save"); return }
        await pause(0.5)
        let world = "ark.preview"
        let check = "const h1 = document.querySelector('h1'); const style = getComputedStyle(h1); return JSON.stringify({ color: style.color, font: style.fontFamily });"
        if let style = try? await browser.currentController?.page.evaluate(check, inWorld: world) as? String {
            note("Boost heading after selecting Serif: \(style)")
        }
        browser.run(command: "edit-site-style")
        await pause(0.6)
        saveVisible("site-style-editor", in: window.attachedSheet ?? window)
        browser.closeSiteStyleEditor()
        await pause(0.6)
        browser.reload()
        await pause(1.5)
        if let style = try? await browser.currentController?.page.evaluate(check, inWorld: world) as? String {
            note("Boost font and CSS after reload: \(style)")
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
        await easelPreview(browser, window: window, page: first)
        await baselinePreviews(browser, window: window, atlas: atlas, otherPage: second)
        await settingsPreviews(browser, window: window)
    }

    private func easelPreview(_ browser: Browser, window: NSWindow, page: URL) async {
        let easelID = browser.library.easels.firstBoard?.id ?? browser.library.easels.addBoard().id
        let addedPage = browser.library.easels.addPage(page, title: "Atlas · Field Guide", to: easelID)
        var editedNote = false
        var editDetail = "note was not created"
        if let noteID = browser.library.easels.addNote(to: easelID) {
            let origin = browser.library.easels.boards.first(where: { $0.id == easelID })?.cards.first(where: { $0.id == noteID })
            browser.library.easels.updateText("A collected page and a note, arranged on one board.", for: noteID, in: easelID)
            browser.library.easels.move(noteID, in: easelID, by: CGSize(width: 48, height: 32))
            if let card = browser.library.easels.boards.first(where: { $0.id == easelID })?.cards.first(where: { $0.id == noteID }) {
                let expectedText = "A collected page and a note, arranged on one board."
                editedNote = {
                    card.text == expectedText
                        && card.x == min(2200, (origin?.x ?? .infinity) + 48)
                        && card.y == min(1650, (origin?.y ?? .infinity) + 32)
                }()
                editDetail = "origin \(origin?.x ?? -1),\(origin?.y ?? -1); card \(card.x),\(card.y); text \(card.text == expectedText)"
            }
        }
        var addedDrawing = false
        if let drawingID = browser.library.easels.addDrawing(to: easelID) {
            browser.library.easels.updateStrokes([[.init(x: 20, y: 28), .init(x: 74, y: 56), .init(x: 142, y: 42)]],
                                                 for: drawingID, in: easelID)
            addedDrawing = browser.library.easels.boards.first(where: { $0.id == easelID })?.cards.first(where: { $0.id == drawingID })?.strokes?.count == 1
        }
        if let capture = await browser.currentController?.page.snapshot() {
            let pasteboard = NSPasteboard.withUniqueName()
            let image = NSBitmapImageRep(cgImage: capture)
            if let png = image.representation(using: .png, properties: [:]) {
                pasteboard.setData(png, forType: .png)
                _ = browser.library.easels.addClipboardImage(to: easelID, pasteboard: pasteboard)
            }
            pasteboard.releaseGlobally()
        }
        browser.openLibrary("easels")
        await pause(1)
        saveVisible("easels", in: window)
        note("Easels preview fixture: page card, editable note, and page capture")
        let pngURL = directory.appending(path: "easel-export.png")
        let zipURL = directory.appending(path: "easels-export.zip")
        let exportedPNG = browser.library.easels.exportPNG(easelID, to: pngURL)
            && FileManager.default.fileExists(atPath: pngURL.path())
        let sharedURL = browser.library.easels.sharePNGURL(for: easelID)
        let sharedPNG = sharedURL.map { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) } ?? false
        let exportedZip = await browser.library.easels.exportAllAsZip(to: zipURL)
            && FileManager.default.fileExists(atPath: zipURL.path())
        let sharedPath = sharedURL?.path(percentEncoded: false) ?? "none"
        if let sharedURL { try? FileManager.default.removeItem(at: sharedURL) }
        note("Easels edit, move, doodle, PNG export, ZIP export, and share preparation: \(addedPage && editedNote && addedDrawing && exportedPNG && exportedZip && sharedPNG) (page \(addedPage), edit \(editedNote), doodle \(addedDrawing), png \(exportedPNG), zip \(exportedZip), share \(sharedPNG)); \(editDetail); share URL \(sharedPath)")
    }

    /// Exercises the optional pinned-link behavior against the same local fixture used by this tour.
    /// Restores both the preference and tab state afterward.
    private func pinnedLinkNavigationCheck(_ browser: Browser, sourceURL: URL, targetURL: URL) async {
        note("pinned-link check started")
        guard let source = browser.currentTab, source.url == sourceURL,
              let page = browser.currentController?.page else {
            note("pinned-link check: fixture tab unavailable")
            return
        }
        note("pinned-link source and WebKit page resolved")
        let originalAction = UserDefaults.standard.object(forKey: Preferences.pinnedLinkActionKey)
        let originalLegacySetting = UserDefaults.standard.object(forKey: Preferences.pinnedLinksOpenInNewTabKey)
        let wasPinned = source.isPinned
        defer {
            if let originalAction {
                UserDefaults.standard.set(originalAction, forKey: Preferences.pinnedLinkActionKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Preferences.pinnedLinkActionKey)
            }
            if let originalLegacySetting {
                UserDefaults.standard.set(originalLegacySetting, forKey: Preferences.pinnedLinksOpenInNewTabKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Preferences.pinnedLinksOpenInNewTabKey)
            }
            if let opened = browser.currentTab, opened.id != source.id, !opened.isPinned { browser.close(opened) }
            browser.select(source)
            if !wasPinned, source.isPinned { browser.togglePinned(source) }
        }
        if !wasPinned {
            browser.togglePinned(source)
            note("pinned-link source pin toggled")
        }
        UserDefaults.standard.set(PinnedLinkAction.today.rawValue, forKey: Preferences.pinnedLinkActionKey)
        guard let targetData = try? JSONEncoder().encode(targetURL.absoluteString),
              let target = String(data: targetData, encoding: .utf8) else {
            note("pinned-link check: could not encode target URL")
            return
        }
        _ = try? await page.evaluate("""
        const link = document.createElement('a'); link.href = \(target); link.textContent = 'Ark pinned-link fixture';
        document.body.append(link); link.click(); return true;
        """, inWorld: "page")
        note("pinned-link Today click returned from WebKit")
        await pause(1.5)
        let opened = browser.currentTab
        let passed = opened?.id != source.id && opened?.url == targetURL && source.isPinned && source.url == sourceURL
        note("pinned-link check: \(passed ? "opened Today tab and kept pin at source" : "did not meet expected tab/pin state")")

        if let opened, opened.id != source.id { browser.close(opened) }
        browser.select(source)
        guard var glanceTarget = URLComponents(url: targetURL, resolvingAgainstBaseURL: false) else {
            note("pinned-link Glance check: could not create a cross-host fixture URL")
            return
        }
        glanceTarget.host = glanceTarget.host == "localhost" ? "127.0.0.1" : "localhost"
        guard let glanceURL = glanceTarget.url,
              let glanceData = try? JSONEncoder().encode(glanceURL.absoluteString),
              let encodedGlanceURL = String(data: glanceData, encoding: .utf8) else {
            note("pinned-link Glance check: could not encode fixture URL")
            return
        }
        UserDefaults.standard.set(PinnedLinkAction.glance.rawValue, forKey: Preferences.pinnedLinkActionKey)
        _ = try? await page.evaluate("""
        const link = document.createElement('a'); link.href = \(encodedGlanceURL); link.textContent = 'Ark pinned-link Glance fixture';
        document.body.append(link); link.click(); return true;
        """, inWorld: "page")
        note("pinned-link Glance click returned from WebKit")
        await pause(1.5)
        let previewed = browser.glance?.url == glanceURL && browser.currentTab?.id == source.id && source.isPinned && source.url == sourceURL
        note("pinned-link Glance check: \(previewed ? "opened cross-host link in Glance and kept pin at source" : "did not meet expected Glance/pin state")")
        browser.closeGlance()
    }

    /// Checks the opt-in close behavior using the previously selected Today tab.
    private func pinnedCloseNavigationCheck(_ browser: Browser, sourceURL: URL, previousURL: URL) async {
        guard let source = browser.currentTab, source.url == sourceURL else {
            note("pinned-close check: fixture tab unavailable")
            return
        }
        let originalSetting = UserDefaults.standard.object(forKey: Preferences.closeTabGoesBackKey)
        let wasPinned = source.isPinned
        defer {
            if let originalSetting {
                UserDefaults.standard.set(originalSetting, forKey: Preferences.closeTabGoesBackKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Preferences.closeTabGoesBackKey)
            }
            if !wasPinned, source.isPinned { browser.togglePinned(source) }
        }
        if !wasPinned { browser.togglePinned(source) }
        browser.newTab(url: previousURL)
        guard let previous = browser.currentTab else {
            note("pinned-close check: previous tab unavailable")
            return
        }
        browser.select(source)
        Preferences.closeTabGoesBack = true
        browser.close(source)
        let passed = browser.currentTab?.id == previous.id && source.isPinned
        note("pinned-close check: \(passed ? "returned to previous tab and kept pin" : "did not meet expected tab/pin state")")
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

    private func pictureInPictureFrameCheck(_ browser: Browser, base: URL) async {
        let tab = browser.newTab(url: base.appending(path: "pip-host.html"))
        guard let page = browser.library.existingController(for: tab)?.page as? WebKitPage,
              let view = page.view as? WKWebView else { note("PiP frame fixture has no WebKit page"); return }
        for _ in 0..<80 {
            if page.registeredFrameIDs.count >= 2 { break }
            await pause(0.1)
        }
        let mainOrigin = tab.url.map { "\($0.scheme ?? "")://\($0.host ?? ""):\($0.port ?? 80)" } ?? ""
        var targetFrame: String?
        var frameOrigins: [String] = []
        for frame in page.registeredFrameIDs {
            guard let value = try? await page.evaluate("return { origin: location.origin, url: location.href, hasVideo: !!document.querySelector('video') };",
                                                        inFrame: frame, inWorld: "ark.pip-frame-check") as? [String: Any],
                  let origin = value["origin"] as? String else { continue }
            frameOrigins.append(origin)
            let expected = URL(string: origin)?.port ?? 80
            if value["hasVideo"] as? Bool == true && "\(URL(string: origin)?.scheme ?? "")://\(URL(string: origin)?.host ?? ""):\(expected)" != mainOrigin {
                targetFrame = frame
            }
        }
        guard let targetFrame else {
            note("cross-origin PiP fixture missing iframe registration/video; origins: \(frameOrigins)")
            return
        }
        for _ in 0..<40 {
            let playing = (try? await page.evaluate("return !!document.querySelector('video') && !document.querySelector('video').paused && document.querySelector('video').readyState >= 2;",
                                                     inFrame: targetFrame, inWorld: "ark.pip-frame-check") as? Bool) == true
            if playing { break }
            await pause(0.2)
        }
        browser.library.videoPictureInPicture.toggle(for: tab, in: browser)
        for _ in 0..<40 where !browser.library.videoPictureInPicture.isFloating(tab.id) { await pause(0.1) }
        let floating = (try? await page.evaluate("return document.querySelector('video')?.webkitPresentationMode === 'picture-in-picture';",
                                                  inFrame: targetFrame, inWorld: "ark.pip-frame-check") as? Bool) == true
        note("registered \(page.registeredFrameIDs.count) frames; cross-origin video entered system PiP: \(floating)")
        browser.library.videoPictureInPicture.stop()
        await view.closeAllMediaPresentations()
        browser.close(tab)
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
        // A profile change closes its former page only after PiP/session cleanup. Resolve the
        // replacement after that lifecycle turn rather than accidentally inspecting the old page.
        await pause(0.3)
        let named = library.controller(for: tab)
        func uses(_ controller: TabController, profileID: UUID?) -> Bool {
            guard let store = (controller.page.view as? WKWebView)?.configuration.websiteDataStore else { return false }
            // A named store's identifier is the profile contract. `isPersistent` is an
            // implementation property rather than an identity guarantee, and named-store
            // persistence is covered by the cookie round-trip above.
            return store.identifier == profileID
        }
        let assigned = named !== original && uses(named, profileID: profile.id)
        library.move(tab, to: shared)
        let keptPage = library.controller(for: tab) === named
        tab.interactionState = Data([1])
        tab.websiteSessionProfileID = profile.id
        library.move(tab, to: standard)
        await pause(0.3)
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
        SnapshotTourWindows.retained.append(settings)
        settings.makeKeyAndOrderFront(nil)
        await pause(0.8)
        saveVisible("space-profiles", in: settings)
        // Keep the captured window alive for AppKit, but stop its live SwiftUI tree from observing
        // the temporary Spaces as the rest of this tour moves and deletes them.
        settings.contentView = NSView(frame: settings.contentView?.bounds ?? .zero)
        browser.nsWindow?.makeKeyAndOrderFront(nil)
    }

    private func arcFolderImportCheck(_ browser: Browser, window: NSWindow, page: URL) async {
        let data = Data("""
        {"sidebar":{"containers":[{"spaces":[{
            "id":"coast","title":"Coastal Survey",
            "newContainerIDs":[{"pinned":{}},"pins"],"containerIDs":["pinned","legacy","unpinned","today"]
        }],"items":[
            {"id":"pins","childrenIds":["root","folder","root"]},
            {"id":"folder","title":"Research","isExpanded":true,"data":{"list":{}},"childrenIds":["work","child","folder"]},
            {"id":"child","title":"References","isExpanded":false,"data":{"list":{}},"childrenIds":["nested"]},
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
            && !space.pinFolders[0].isCollapsed && space.pinFolders[1].isCollapsed
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

    private func pinFolderPreview(_ browser: Browser, window: NSWindow, base: URL) async {
        let space = browser.currentSpace
        guard let tab = browser.currentTab, !tab.isPinned,
              let folder = space.addPinFolder(named: "Coastal Survey"),
              let child = space.addPinFolder(named: "Reference Pages", inside: folder.id) else { return }
        var secondTab: BrowserTab?
        var bulkFolderID: UUID?
        defer {
            if let bulkFolderID { space.removePinFolder(bulkFolderID) }
            space.removePinFolder(child.id)
            space.removePinFolder(folder.id)
            if tab.isPinned { browser.togglePinned(tab) }
            if let secondTab, secondTab.isPinned { browser.togglePinned(secondTab) }
        }
        await pause(0.8)
        let nested = await drag(tab, into: child.id, in: space, browser: browser)
        note("drag from Today into nested pin folder: \(nested)")
        guard nested else { return }
        saveVisible("pinned-folders", in: window)
        let second = browser.newTab(url: base.appending(path: "atlas.html"))
        secondTab = second
        await pause(0.4)
        let secondNested = await drag(second, into: child.id, in: space, browser: browser)
        note("add second pin to folder for reorder and selection checks: \(secondNested)")
        guard secondNested else { return }
        let initialFolderOrder = space.pinned.filter { $0.pinFolderID == child.id }.map(\.id)
        let reordered = await dragToEndOfFolder(tab, after: second, folderID: child.id, in: space, browser: browser)
        let expectedOrder = [second.id, tab.id]
        let finalFolderOrder = space.pinned.filter { $0.pinFolderID == child.id }.map(\.id)
        note("drag reorders pins within folder: target and order \(reordered), started correctly \(initialFolderOrder == [tab.id, second.id]), order \(finalFolderOrder == expectedOrder)")

        let bulkFolder = space.addPinFolder(named: "Selected Pins")
        bulkFolderID = bulkFolder?.id
        if let bulkFolder {
            let orderBeforeBulkMove = space.pinned.map(\.id)
            let childPinIDsBeforeBulkMove = Set(space.pinned.filter { $0.pinFolderID == child.id }.map(\.id))
            let firstClick = await clickSidebarPin(second, modifiers: .command, browser: browser, window: window)
            let secondClick = await clickSidebarPin(tab, modifiers: .command, browser: browser, window: window)
            let selected = browser.selectedSidebarPinIDs == Set([second.id, tab.id])
            browser.moveSelectedPins(into: bulkFolder.id)
            let moved = selected && space.pinned.filter { $0.pinFolderID == bulkFolder.id }.map(\.id) == expectedOrder
                && browser.canUndoSidebarPinMove
            let movedOrder = space.pinned.filter { $0.pinFolderID == bulkFolder.id }.map(\.id)
            let moveUndoAvailable = browser.canUndoSidebarPinMove
            if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                                            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                            context: nil, characters: "z", charactersIgnoringModifiers: "z",
                                            isARepeat: false, keyCode: 6) {
                NSApp.postEvent(event, atStart: true)
                await pause(0.25)
            }
            let shortcutUndid = !browser.canUndoSidebarPinMove
            let restoredOrder = space.pinned.map(\.id) == orderBeforeBulkMove
            let restoredFolderPins = Set(space.pinned.filter { $0.pinFolderID == child.id }.map(\.id)) == childPinIDsBeforeBulkMove
            let restoredFolderExists = space.pinFolders.contains(where: { $0.id == bulkFolder.id })
            let restoredDestinationEmpty = space.pinned.filter { $0.pinFolderID == bulkFolder.id }.isEmpty
            note("Command-clicks selected both rows: \(firstClick && secondClick && selected); bulk move \(moved) to expected order \(movedOrder == expectedOrder), undo available \(moveUndoAvailable), ⌘Z handled \(shortcutUndid), restore order \(restoredOrder), source folder assignments \(restoredFolderPins), destination folder exists \(restoredFolderExists), destination empty \(restoredDestinationEmpty)")
            if browser.canUndoSidebarPinMove { browser.undoSidebarPinMove() }
            browser.clearSidebarPinSelection()
            let shiftAnchor = await clickSidebarPin(second, modifiers: .command, browser: browser, window: window)
            let shiftRange = await clickSidebarPin(tab, modifiers: .shift, browser: browser, window: window)
            note("Shift-click selected the visible range of two pins: \(shiftAnchor && shiftRange && browser.selectedSidebarPinIDs == Set([second.id, tab.id]))")
            browser.clearSidebarPinSelection()
        }
        browser.select(tab)
        let moved = await drag(tab, into: folder.id, in: space, browser: browser)
        let returned = moved ? await drag(tab, into: child.id, in: space, browser: browser) : false
        note("drag a pin between folders in both directions: \(moved && returned)")
        let todayBeforeOpenAll = Set(space.today.map(\.id))
        let selectedBeforeOpenAll = browser.currentTab?.id
        let expectedOpenAll = space.pinned.filter { $0.pinFolderID == child.id }.compactMap(\.url)
        if let parent = space.pinFolders.first(where: { $0.id == folder.id }) {
            let todayCountBeforeOpenAll = space.today.count
            browser.openAllPinnedTabs(in: parent, space: space)
            let opened = space.today.filter { !todayBeforeOpenAll.contains($0.id) }
            for _ in 0..<40 where opened.contains(where: { $0.url == nil }) { await pause(0.1) }
            let openedInOrder = opened.compactMap(\.url) == expectedOpenAll
            let keptSelection = browser.currentTab?.id == selectedBeforeOpenAll
            note("Open All nested order/count \(openedInOrder)/\(opened.count == expectedOpenAll.count); keeps selection \(keptSelection); folder no-feed \(parent.feed == nil), today count \(todayCountBeforeOpenAll)->\(space.today.count); expected \(expectedOpenAll.map(\.absoluteString)), opened \(opened.compactMap(\.url).map(\.absoluteString))")
            for openedTab in opened { browser.close(openedTab) }
        }
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

    private func dragToEndOfFolder(_ tab: BrowserTab, after sibling: BrowserTab, folderID: UUID,
                                   in space: Space, browser: Browser) async -> Bool {
        guard let dragging = browser.sidebarDragging,
              let sourceFrame = dragging.rowFrames[tab.id],
              dragging.rowFrames[sibling.id] != nil else { return false }
        let source = CGPoint(x: sourceFrame.midX, y: sourceFrame.midY)
        dragging.changed(tab, from: source, to: source, in: space, browser: browser)
        let expectedCount = space.pinned.filter { $0.pinFolderID == folderID && $0.id != tab.id }.count
        var targetedEnd = false
        for _ in 0..<24 {
            await pause(0.04)
            guard let frame = dragging.rowFrames[sibling.id] else { continue }
            let destination = CGPoint(x: frame.midX, y: frame.maxY - 1)
            dragging.changed(tab, from: source, to: destination, in: space, browser: browser)
            if dragging.target == .folderSlot(folderID, expectedCount) { targetedEnd = true; break }
        }
        note("within-folder drag reached the append slot: \(targetedEnd)")
        dragging.ended(tab, in: space, browser: browser)
        for _ in 0..<40 where dragging.isLifted(tab.id) { await pause(0.1) }
        await pause(0.3)
        return targetedEnd && !dragging.isLifted(tab.id)
            && space.pinned.filter { $0.pinFolderID == folderID }.map(\.id).last == tab.id
    }

    private func clickSidebarPin(_ tab: BrowserTab, modifiers: NSEvent.ModifierFlags,
                                 browser: Browser, window: NSWindow) async -> Bool {
        guard let dragging = browser.sidebarDragging,
              let frame = dragging.rowFrames[tab.id] else { return false }
        let layoutPoint = CGPoint(x: frame.midX + dragging.originInWindow.x,
                                  y: frame.midY + dragging.originInWindow.y)
        let point = CGPoint(x: layoutPoint.x,
                            y: (window.contentView?.bounds.height ?? window.frame.height) - layoutPoint.y)
        guard let down = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: modifiers,
                                            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                            context: nil, eventNumber: 0, clickCount: 1, pressure: 1),
              let up = NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: modifiers,
                                          timestamp: ProcessInfo.processInfo.systemUptime + 0.01, windowNumber: window.windowNumber,
                                          context: nil, eventNumber: 0, clickCount: 1, pressure: 0) else { return false }
        NSApp.postEvent(down, atStart: false)
        NSApp.postEvent(up, atStart: false)
        await pause(0.25)
        let selected = browser.selectedSidebarPinIDs.contains(tab.id)
        note("Command-click row selected \(tab.displayTitle): \(selected); current tab is row: \(browser.currentTab?.id == tab.id)")
        return selected
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
            const rect = document.querySelector("h1").getBoundingClientRect();
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
        let pageURL = URL(string: "https://reference.ark.local/design")!
        let noteHTML = "<!doctype html><meta charset='utf-8'><title>Design reference</title><body style='margin:0;background:#202126;color:#e9e9eb'><main style='font: 24px -apple-system; max-width: 720px; margin: 12vh auto'><h1 style='color:#202126'>Collect design references</h1><p>A page-bound note stays attached to its source.</p></main></body>"
        let noteTab = browser.newTab(url: pageURL)
        browser.select(noteTab)
        browser.library.existingController(for: noteTab)?.page.loadHTML(noteHTML, baseURL: pageURL)
        await pause(0.5)
        browser.library.margin.add(MarginNote(url: pageURL, pageTitle: "Design reference",
                                              anchor: .init(quote: "Collect design references"),
                                              body: "Keep this reference with the source page."))
        browser.showPanel("notes")
        await pause(0.6)
        saveVisible("notes-panel", in: window)
        browser.panel = nil
        let syncFolder = directory.appending(path: "sync-fixture", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: syncFolder, withIntermediateDirectories: true)
            try browser.library.syncCoordinator.selectFolder(syncFolder)
            await browser.library.syncNow()
            note("sync settings fixture: folder selected, state \(browser.library.syncCoordinator.state)")

            let peer = BrowserSyncCoordinator(configurationURL: directory.appending(path: "peer-sync.json"))
            try peer.selectFolder(syncFolder)
            peer.setSharingOpenTabs(true)
            let remoteTab = BrowserTab(url: URL(string: "https://tabs.ark.local/review")!, title: "Remote review")
            let currentRecords = browser.library.regularSpaces.map(\.record)
            let remoteSpaces = currentRecords.map { source -> SpaceRecord in
                guard source.id == browser.currentSpace.id else { return source }
                var space = source
                space.today = [remoteTab.record]
                return space
            }
            let peerSnapshot = BrowserSnapshot(
                spaces: remoteSpaces, selectedSpaceID: browser.currentSpace.id,
                favorites: browser.library.favorites(for: nil), archive: browser.library.archive.map(\.record),
                settings: browser.library.settings, saved: nil,
                profileFavorites: browser.library.favoritesByProfile
            )
            _ = await peer.synchronize(peerSnapshot)
            await browser.library.syncNow()
            let received = browser.library.syncCoordinator.otherDevices.contains { device in
                device.spaces.contains { space in
                    space.id == browser.currentSpace.id && space.tabs.contains { $0.url == remoteTab.url }
                }
            }
            await browser.library.syncNow()
            let retained = browser.library.syncCoordinator.otherDevices.contains { device in
                device.spaces.contains { space in space.tabs.contains { $0.url == remoteTab.url } }
            }
            peer.setSharingOpenTabs(false)
            _ = await peer.synchronize(peerSnapshot)
            await browser.library.syncNow()
            let withdrawn = !browser.library.syncCoordinator.otherDevices.contains { device in
                device.spaces.contains { space in space.tabs.contains { $0.url == remoteTab.url } }
            }
            note("shared-folder tab index arrived, survived another device sync, and cleared on opt-out: \(received && retained && withdrawn)")
        } catch {
            note("sync settings fixture failed: \(error.localizedDescription)")
        }
        for (pane, file) in [("spaces", "shared-collections"), ("routing", "space-routing"), ("shortcuts", "custom-shortcuts"), ("privacy", "ad-blocker"), ("general", "idle-page-unloading"), ("sync", "sync-settings")] {
            // Host the real settings view directly: the Settings scene may not
            // have a registered open action during a standalone Debug launch.
            defaults.set(pane, forKey: "settingsTab")
            let settings = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 620),
                                    styleMask: [.titled, .closable], backing: .buffered, defer: false)
            settings.title = SettingsView.panes.first { $0.id == pane }?.title ?? pane
            settings.contentView = NSHostingView(rootView: SettingsView()
                .environment(browser.library).environment(delegate.updates))
            SnapshotTourWindows.retained.append(settings)
            settings.center()
            settings.makeKeyAndOrderFront(nil)
            await pause(0.8)
            saveVisible(file, in: settings)
            settings.contentView = NSView(frame: settings.contentView?.bounds ?? .zero)
            settings.orderOut(nil)
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
