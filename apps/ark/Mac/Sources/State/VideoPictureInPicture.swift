import AppKit
import WebKit

/// Owns only the video Ark floated automatically. The call window and site-initiated PiP are separate.
@MainActor
final class VideoPictureInPicture {
    private var request: Task<Void, Never>?
    private var tabID: UUID?
    private weak var view: WKWebView?
    private var dismissal: (tabID: UUID, task: Task<Void, Never>)?

    func visibleTabsChanged(in browser: Browser, from previous: [UUID], to current: [UUID]) {
        if let tabID, current.contains(tabID) { stop() }
        guard Preferences.automaticVideoPiP, browser.library.activeWindow === browser,
              browser.nsWindow?.isVisible == true, request == nil else { return }
        let hidden = previous.filter { !current.contains($0) }
        guard !hidden.isEmpty else { return }
        request = Task { [weak self, weak browser] in
            guard let self else { return }
            defer { request = nil }
            guard let library = browser?.library else { return }
            if let view, await Self.run("return Array.from(document.querySelectorAll('video')).some(video => video.webkitPresentationMode === 'picture-in-picture');", in: view) {
                return
            }
            tabID = nil
            view = nil
            for id in hidden {
                guard !Task.isCancelled, Preferences.automaticVideoPiP else { return }
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
                tabID = id
                view = candidate
                return
            }
        }
    }

    func stop() {
        request?.cancel()
        request = nil
        if let tabID, let view { dismiss(tabID, view: view) }
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
        let task = Task { @MainActor [weak self] in
            await view.closeAllMediaPresentations()
            if self?.dismissal?.tabID == id { self?.dismissal = nil }
        }
        dismissal = (id, task)
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

    private static func run(_ script: String, in view: WKWebView) async -> Bool {
        (try? await view.callAsyncJavaScript(script, arguments: [:], in: nil,
                                             contentWorld: .world(name: "ark.video-pip"))) as? Bool == true
    }
}
