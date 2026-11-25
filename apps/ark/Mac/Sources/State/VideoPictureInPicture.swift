import AppKit
import WebKit
import BrowserCore
import BrowserEngine
import WebKitEngine

/// Owns only the video Ark floated automatically. The call window and site-initiated PiP are separate.
@MainActor
final class VideoPictureInPicture {
    private var request: Task<Void, Never>?
    private var requestID: UUID?
    private var tabID: UUID?
    private var returnsOnActivation = false
    private var pendingAppSwitch = false
    private weak var view: WKWebView?
    private var dismissal: (id: UUID, tabID: UUID, task: Task<Void, Never>)?
    private var awayWatch: NSObjectProtocol?
    private weak var awayWindow: NSWindow?
    private weak var awayBrowser: Browser?
    private var awayCandidates: [UUID] = []

    func isFloating(_ id: UUID) -> Bool { tabID == id }

    func visibleTabsChanged(in browser: Browser, from previous: [UUID], to current: [UUID]) {
        stopAwayWatch()
        if let tabID, current.contains(tabID) { stop() }
        startAutomatically(in: browser, candidates: previous.filter { !current.contains($0) }, applicationInactive: false)
    }

    func applicationActivityChanged(in browser: Browser, active: Bool) {
        if active { stopAwayWatch() }
        guard browser.library.activeWindow === browser else { return }
        if active {
            if pendingAppSwitch {
                request?.cancel()
                request = nil
                requestID = nil
                pendingAppSwitch = false
            }
            guard returnsOnActivation else { return }
            if tabID.map(browser.visibleTabIDs.contains) ?? true { stop() }
            returnsOnActivation = false
        } else {
            watchForWindowLeavingSight(in: browser, candidates: browser.visibleTabIDs)
        }
    }

    private func isAway(from tab: BrowserTab, in browser: Browser, applicationInactive: Bool) -> Bool {
        if applicationInactive {
            return !NSApp.isActive && browser.library.activeWindow === browser
                && browser.visibleTabIDs.contains(tab.id)
                && browser.nsWindow?.occlusionState.contains(.visible) != true
        }
        return browser.library.window(showing: tab) == nil
    }

    /// Keep a playing page inline while Ark is merely unfocused but still visible. Lift it only
    /// after its window becomes occluded; a window on another display stays where the person left it.
    private func watchForWindowLeavingSight(in browser: Browser, candidates: [UUID]) {
        stopAwayWatch()
        guard !NSApp.isActive, Preferences.automaticVideoPiP, browser.library.activeWindow === browser,
              browser.nsWindow?.isVisible == true, !candidates.isEmpty,
              let window = browser.nsWindow else { return }
        if !window.occlusionState.contains(.visible) {
            startAutomatically(in: browser, candidates: candidates, applicationInactive: true)
            return
        }
        if let shown = window.screen,
           let pointerScreen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }),
           shown != pointerScreen { return }

        awayWindow = window
        awayBrowser = browser
        awayCandidates = candidates
        awayWatch = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !NSApp.isActive, let browser = self.awayBrowser,
                      let window = self.awayWindow, !window.occlusionState.contains(.visible) else { return }
                let candidates = self.awayCandidates
                self.stopAwayWatch()
                self.startAutomatically(in: browser, candidates: candidates, applicationInactive: true)
            }
        }
    }

    private func stopAwayWatch() {
        if let awayWatch { NotificationCenter.default.removeObserver(awayWatch) }
        awayWatch = nil
        awayWindow = nil
        awayBrowser = nil
        awayCandidates = []
    }

    private func startAutomatically(in browser: Browser, candidates: [UUID], applicationInactive: Bool) {
        guard Preferences.automaticVideoPiP, browser.library.activeWindow === browser,
              browser.nsWindow?.isVisible == true, request == nil, !candidates.isEmpty else { return }
        let requestID = UUID()
        self.requestID = requestID
        pendingAppSwitch = applicationInactive
        request = Task { [weak self, weak browser] in
            guard let self else { return }
            defer {
                if self.requestID == requestID {
                    self.request = nil
                    self.requestID = nil
                    self.pendingAppSwitch = false
                }
            }
            guard !Task.isCancelled, self.requestID == requestID else { return }
            guard let browser else { return }
            let library = browser.library
            tabID = nil
            view = nil
            for id in candidates {
                guard !Task.isCancelled, Preferences.automaticVideoPiP else { return }
                guard library.videoMiniPlayer.tabID != id else { continue }
                guard let tab = library.tab(id: id), !tab.isPrivate, tab.call == nil,
                      !library.agents.isInAgentSpace(tab), isAway(from: tab, in: browser, applicationInactive: applicationInactive),
                      let controller = library.existingController(for: tab),
                      !controller.page.state.isCapturing, let candidate = controller.page.view as? WKWebView else { continue }
                Self.enableNativeMode(in: candidate)
                let result = await Self.start(page: controller.page, view: candidate)
                guard result == "in" || result == "already" else { continue }
                guard !Task.isCancelled, Preferences.automaticVideoPiP, library.tab(id: id) === tab,
                      library.existingController(for: tab)?.page.view === candidate,
                      isAway(from: tab, in: browser, applicationInactive: applicationInactive) else {
                    await candidate.closeAllMediaPresentations()
                    return
                }
                if dismissal?.tabID == id { dismissal = nil }
                tabID = id
                returnsOnActivation = applicationInactive
                view = candidate
                return
            }
        }
    }

    /// Search’s ⇧⌘P action: toggle the current page’s largest video into system PiP.
    func toggle(for tab: BrowserTab, in browser: Browser) {
        guard !tab.isPrivate, tab.call == nil, !browser.library.agents.isInAgentSpace(tab),
              browser.library.activeWindow === browser,
              let page = browser.library.existingController(for: tab)?.page,
              let candidate = page.view as? WKWebView else {
            browser.showToast("Picture in Picture is unavailable for this tab")
            return
        }
        if tabID == tab.id { stop(); return }
        stop()
        Self.enableNativeMode(in: candidate)
        let requestID = UUID()
        self.requestID = requestID
        request = Task { [weak self, weak browser, weak tab] in
            guard let self, let browser, let tab else { return }
            defer {
                if self.requestID == requestID {
                    self.request = nil
                    self.requestID = nil
                }
            }
            if let dismissal = self.dismissal, dismissal.tabID != tab.id { await dismissal.task.value }
            guard !Task.isCancelled, browser.currentTab === tab,
                  browser.library.existingController(for: tab)?.page.view === candidate else { return }
            let result = await Self.toggle(page: page, view: candidate)
            guard !Task.isCancelled, self.requestID == requestID else {
                if result == "in" { await candidate.closeAllMediaPresentations() }
                return
            }
            switch result {
            case "in":
                if self.dismissal?.tabID == tab.id { self.dismissal = nil }
                self.tabID = tab.id
                self.view = candidate
            case "none": browser.showToast("No video is available for Picture in Picture")
            case "refused": browser.showToast("This page does not allow Picture in Picture")
            default: break
            }
        }
    }

    func stop() {
        stopAwayWatch()
        returnsOnActivation = false
        pendingAppSwitch = false
        request?.cancel()
        request = nil
        requestID = nil
        if let tabID, let view { _ = dismiss(tabID, view: view) }
        view = nil
        tabID = nil
    }

    /// An Ark-owned native PiP window must close before its WebView is torn down.
    /// Other unloads complete immediately, including site-owned PiP.
    func beforeTabUnload(_ id: UUID, then completion: @escaping @MainActor () -> Void) {
        if tabID == id, let view {
            request?.cancel()
            request = nil
            self.view = nil
            tabID = nil
            let task = dismiss(id, view: view)
            Task { await task.value; completion() }
        } else if let dismissal, dismissal.tabID == id {
            Task { await dismissal.task.value; completion() }
        } else {
            completion()
        }
    }

    private func dismiss(_ id: UUID, view: WKWebView) -> Task<Void, Never> {
        if let dismissal, dismissal.tabID == id { return dismissal.task }
        let dismissalID = UUID()
        let task = Task { @MainActor [weak self] in
            await view.closeAllMediaPresentations()
            if self?.dismissal?.id == dismissalID { self?.dismissal = nil }
        }
        dismissal = (dismissalID, id, task)
        return task
    }

    private static func enableNativeMode(in webView: WKWebView) {
        // The macOS SDK has no public WKWebView configuration property for this preference.
        let preferences = webView.configuration.preferences
        let selector = NSSelectorFromString("_setAllowsPictureInPictureMediaPlayback:")
        guard preferences.responds(to: selector) else { return }
        typealias Setter = @convention(c) (AnyObject, Selector, Bool) -> Void
        unsafeBitCast(preferences.method(for: selector), to: Setter.self)(preferences, selector, true)
    }

    private struct VideoChoice {
        let frameID: String?
        let index: Int
        let area: Double
        let floating: Bool
        let supported: Bool
    }

    private static func frameIDs(in page: any EnginePage) -> [String?] {
        guard let page = page as? WebKitPage, !page.registeredFrameIDs.isEmpty else { return [nil] }
        return page.registeredFrameIDs.map(Optional.some)
    }

    private static func evaluate(_ script: String, page: any EnginePage, view: WKWebView,
                                 frameID: String?, arguments: [String: Any] = [:]) async -> Any? {
        if let page = page as? WebKitPage {
            return try? await page.evaluate(script, arguments: arguments, inFrame: frameID, inWorld: "ark.video-pip")
        }
        guard frameID == nil else { return nil }
        return try? await view.callAsyncJavaScript(script, arguments: arguments, in: nil,
                                                    contentWorld: .world(name: "ark.video-pip"))
    }

    private static func bestVideo(in page: any EnginePage, view: WKWebView, automatic: Bool) async -> VideoChoice? {
        var best: VideoChoice?
        for frameID in frameIDs(in: page) {
            guard let value = await evaluate(probeScript, page: page, view: view, frameID: frameID,
                                             arguments: ["automatic": automatic]) as? [String: Any],
                  let state = value["state"] as? String, let index = value["index"] as? Int else { continue }
            let choice = VideoChoice(frameID: frameID, index: index,
                                     area: value["area"] as? Double ?? 0,
                                     floating: state == "floating",
                                     supported: value["supported"] as? Bool ?? false)
            if choice.floating { return choice }
            if state == "candidate", choice.area > (best?.area ?? 0) { best = choice }
        }
        return best
    }

    private static func perform(_ choice: VideoChoice, mode: String, page: any EnginePage, view: WKWebView) async -> Bool {
        (await evaluate(performScript, page: page, view: view, frameID: choice.frameID,
                        arguments: ["index": choice.index, "mode": mode])) as? Bool == true
    }

    private static func start(page: any EnginePage, view: WKWebView) async -> String {
        guard let choice = await bestVideo(in: page, view: view, automatic: true) else { return "none" }
        if choice.floating { return "already" }
        guard choice.supported else { return "refused" }
        return await perform(choice, mode: "picture-in-picture", page: page, view: view) ? "in" : "refused"
    }

    private static func toggle(page: any EnginePage, view: WKWebView) async -> String {
        guard let choice = await bestVideo(in: page, view: view, automatic: false) else { return "none" }
        if choice.floating {
            return await perform(choice, mode: "inline", page: page, view: view) ? "out" : "refused"
        }
        guard choice.supported else { return "refused" }
        return await perform(choice, mode: "picture-in-picture", page: page, view: view) ? "in" : "refused"
    }

    private static let probeScript = """
        const mode = 'picture-in-picture';
        const isAutomatic = Boolean(automatic);
        const videos = Array.from(document.querySelectorAll('video'));
        for (let i = 0; i < videos.length; i++) {
            if (videos[i].webkitPresentationMode === mode) return { state: 'floating', index: i, area: 0, supported: true };
        }
        let best = null;
        let area = 0;
        let supported = false;
        for (let i = 0; i < videos.length; i++) {
            const video = videos[i];
            if (video.readyState < 2 || video.hasAttribute('disablepictureinpicture')) continue;
            if (isAutomatic && (video.paused || video.ended || video.muted || video.volume === 0 || video.srcObject)) continue;
            const rect = video.getBoundingClientRect();
            const width = Math.max(0, Math.min(innerWidth, rect.right) - Math.max(0, rect.left));
            const height = Math.max(0, Math.min(innerHeight, rect.bottom) - Math.max(0, rect.top));
            const size = width * height;
            if (isAutomatic && (width < 160 || height < 90)) continue;
            if (size > area) { best = i; area = size; supported = Boolean(video.webkitSupportsPresentationMode?.(mode)); }
        }
        return best == null ? { state: 'none' } : { state: 'candidate', index: best, area, supported };
        """

    private static let performScript = """
        const video = document.querySelectorAll('video')[index];
        if (!video || typeof video.webkitSetPresentationMode !== 'function') return false;
        try { video.webkitSetPresentationMode(mode); return true; } catch { return false; }
        """
}
