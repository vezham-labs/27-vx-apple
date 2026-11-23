import AppKit
import WebKit
import BrowserCore

/// Owns only the video Ark floated automatically. The call window and site-initiated PiP are separate.
@MainActor
final class VideoPictureInPicture {
    private var request: Task<Void, Never>?
    private var requestID: UUID?
    private var tabID: UUID?
    private weak var view: WKWebView?
    private var dismissal: (id: UUID, tabID: UUID, task: Task<Void, Never>)?

    func visibleTabsChanged(in browser: Browser, from previous: [UUID], to current: [UUID]) {
        if let tabID, current.contains(tabID) { stop() }
        guard Preferences.automaticVideoPiP, browser.library.activeWindow === browser,
              browser.nsWindow?.isVisible == true, request == nil else { return }
        let hidden = previous.filter { !current.contains($0) }
        guard !hidden.isEmpty else { return }
        let requestID = UUID()
        self.requestID = requestID
        request = Task { [weak self, weak browser] in
            guard let self else { return }
            defer {
                if self.requestID == requestID {
                    self.request = nil
                    self.requestID = nil
                }
            }
            guard !Task.isCancelled, self.requestID == requestID else { return }
            guard let library = browser?.library else { return }
            if let view, await Self.run("return Array.from(document.querySelectorAll('video')).some(video => video.webkitPresentationMode === 'picture-in-picture');", in: view) {
                return
            }
            tabID = nil
            view = nil
            for id in hidden {
                guard !Task.isCancelled, Preferences.automaticVideoPiP else { return }
                guard library.videoMiniPlayer.tabID != id else { continue }
                guard let tab = library.tab(id: id), !tab.isPrivate, tab.call == nil,
                      !library.agents.isInAgentSpace(tab), library.window(showing: tab) == nil,
                      let page = library.existingController(for: tab)?.page,
                      !page.state.isCapturing, let candidate = page.view as? WKWebView else { continue }
                Self.enableNativeMode(in: candidate)
                guard await Self.run(Self.startScript, in: candidate) else { continue }
                guard !Task.isCancelled, Preferences.automaticVideoPiP, library.tab(id: id) === tab,
                      library.existingController(for: tab)?.page.view === candidate,
                      library.window(showing: tab) == nil else {
                    await candidate.closeAllMediaPresentations()
                    return
                }
                if dismissal?.tabID == id { dismissal = nil }
                tabID = id
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
            let result = await Self.result(Self.toggleScript, in: candidate)
            guard !Task.isCancelled, self.requestID == requestID else {
                if (result as? String) == "in" { await candidate.closeAllMediaPresentations() }
                return
            }
            switch result as? String {
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

    private static let startScript = """
        const mode = 'picture-in-picture';
        let best = null;
        let area = 0;
        for (const video of document.querySelectorAll('video')) {
            if (video.webkitPresentationMode === mode) return false;
            if (video.paused || video.ended || video.muted || video.volume === 0 || video.srcObject || video.readyState < 2 ||
                video.hasAttribute('disablepictureinpicture') || !video.webkitSupportsPresentationMode?.(mode)) continue;
            const rect = video.getBoundingClientRect();
            const width = Math.min(innerWidth, rect.right) - Math.max(0, rect.left);
            const height = Math.min(innerHeight, rect.bottom) - Math.max(0, rect.top);
            const size = width * height;
            if (width >= 160 && height >= 90 && size > area) { best = video; area = size; }
        }
        if (!best) return false;
        try { best.webkitSetPresentationMode(mode); }
        catch { return false; }
        return true;
        """

    private static let toggleScript = """
        const mode = 'picture-in-picture';
        const videos = Array.from(document.querySelectorAll('video'));
        const floating = videos.find(video => video.webkitPresentationMode === mode);
        if (floating) {
            try { floating.webkitSetPresentationMode('inline'); return 'out'; }
            catch { return 'refused'; }
        }
        let best = null;
        let area = 0;
        for (const video of videos) {
            if (video.readyState < 2 || video.hasAttribute('disablepictureinpicture') ||
                !video.webkitSupportsPresentationMode?.(mode)) continue;
            const rect = video.getBoundingClientRect();
            const width = Math.max(0, Math.min(innerWidth, rect.right) - Math.max(0, rect.left));
            const height = Math.max(0, Math.min(innerHeight, rect.bottom) - Math.max(0, rect.top));
            if (width * height > area) { best = video; area = width * height; }
        }
        if (!best) return 'none';
        try { best.webkitSetPresentationMode(mode); return 'in'; }
        catch { return 'refused'; }
        """

    private static func run(_ script: String, in view: WKWebView) async -> Bool {
        (await result(script, in: view)) as? Bool == true
    }

    private static func result(_ script: String, in view: WKWebView) async -> Any? {
        try? await view.callAsyncJavaScript(script, arguments: [:], in: nil,
                                            contentWorld: .world(name: "ark.video-pip"))
    }
}
