import AppKit
import Observation
import BrowserCore
import BrowserEngine
import Suggest
import WebKit

/// Ties one tab to its live page: mirrors the page's state onto the tab, and answers the page's
/// questions for the browser.
@MainActor
final class TabController: EnginePageDelegate {
    let tab: BrowserTab
    /// The engine the page runs on (`EngineInfo.id`): WebKit, or Chromium for a call tab.
    let engineID: String
    private(set) var page: (any EnginePage)!
    private weak var library: Library?
    weak var linkPreview: LinkPreviewWindow?
    /// The window showing this tab, if any.
    private var window: Browser? { library?.window(showing: tab) }
    /// How the next finished load should count in history.
    private var pendingSource: Frecency.VisitSource?
    private var typedRedirectSource: (url: URL, at: Date, started: Bool)?
    private(set) var navigationGeneration: UInt = 0
    /// The largest inner scrolling surface captured when the WebView was unloaded.
    private var pendingInnerScrollRestore: String?
    private var canCaptureInnerScroll = true
    /// The page's process died while it was out of sight. Reload when it's shown again.
    private var needsRecovery = false
    private var lastTermination: Date?
    private var askingApps: Set<String> = []
    private var declinedApps: Set<String> = []

    init(tab: BrowserTab, library: Library, engineID: String? = nil, makePage: (TabController) -> any EnginePage) {
        self.tab = tab
        self.engineID = engineID ?? library.engine.info.id
        self.library = library
        page = makePage(self)
        page.delegate = self
        if let host = tab.url?.host() { setZoom(Preferences.zoom(for: host)) }
        mirror()
    }

    /// Copies the page's live state onto the tab whenever it changes.
    private func mirror() {
        guard let page else { return }
        withObservationTracking {
            let s = page.state
            _ = (s.url, s.title, s.progress, s.isLoading, s.canGoBack, s.canGoForward, s.isSecure, s.camera, s.microphone)
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.sync()
                self?.mirror()
            }
        }
        sync()
    }

    private func sync() {
        guard let s = page?.state else { return }
        if let url = s.url, tab.url != url { tab.url = url }
        if !s.title.isEmpty, tab.title != s.title { tab.title = s.title }
        // Only real changes, so views watching the tab don't redraw for nothing.
        if tab.estimatedProgress != s.progress { tab.estimatedProgress = s.progress }
        if tab.isLoading != s.isLoading { tab.isLoading = s.isLoading }
        if tab.canGoBack != s.canGoBack { tab.canGoBack = s.canGoBack }
        if tab.canGoForward != s.canGoForward { tab.canGoForward = s.canGoForward }
        let call = s.camera == .off && s.microphone == .off ? nil : TabCall(camera: s.camera == .on, microphone: s.microphone == .on)
        if tab.call != call { tab.call = call }
    }

    func load(_ url: URL, source: Frecency.VisitSource, rememberTypedAddress: Bool = false) {
        navigationGeneration &+= 1
        typedRedirectSource = nil
        if linkPreview == nil, let library, library.needsEngineSwap(self, to: url) {
            library.swapEngine(of: tab, to: url, source: source, rememberTypedAddress: rememberTypedAddress)
            return
        }
        pendingInnerScrollRestore = nil
        library?.discardSleepingScrollState(for: tab.id)
        pendingSource = source
        tab.loadError = nil
        page.load(url)
        if rememberTypedAddress { self.rememberTypedAddress(url) }
    }

    func rememberTypedAddress(_ url: URL) {
        guard !tab.isPrivate, let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              url.host() != nil, url.user == nil, url.password == nil else { return }
        typedRedirectSource = (library?.cleanedNavigationURL(url) ?? url, .now, false)
    }

    func stopLoading() {
        navigationGeneration &+= 1
        typedRedirectSource = nil
        page.stopLoading()
    }

    func registerPromotedPage(url: URL, source: Frecency.VisitSource) {
        pendingSource = source
        self.page(page, didCommit: url)
        self.page(page, didFinish: url, title: page.state.title)
    }

    func freeze() {
        if let state = page?.sessionState() {
            tab.interactionState = state
            tab.websiteSessionProfileID = (page.view as? WKWebView)?.configuration.websiteDataStore.identifier
        }
    }

    func captureInnerScroll() async -> String? {
        guard canCaptureInnerScroll, !tab.isPrivate, let page,
              let position = try? await page.evaluate(Self.captureInnerScroll, inWorld: "page") as? String,
              position.utf8.count <= 16 * 1024 else { return nil }
        return position
    }

    func discardInnerScrollState() {
        canCaptureInnerScroll = false
        pendingInnerScrollRestore = nil
    }

    func restoreInnerScroll(_ position: String) {
        pendingInnerScrollRestore = position
    }

    private static let captureInnerScroll = #"""
        return (() => {
          try {
            const viewport = innerWidth * innerHeight;
            let best = null, area = 0, visited = 0;
            const walk = document.createTreeWalker(document.body || document.documentElement, NodeFilter.SHOW_ELEMENT);
            for (let el = walk.currentNode; el && visited++ < 60000; el = walk.nextNode()) {
              if (el === document.body || el === document.documentElement || !(el.scrollTop || el.scrollLeft)) continue;
              const next = el.clientWidth * el.clientHeight;
              if (next > area) { best = el; area = next; }
            }
            if (!best || area < viewport / 4) return null;
            const step = (el) => {
              let index = 1;
              for (let sibling = el.previousElementSibling; sibling; sibling = sibling.previousElementSibling)
                if (sibling.tagName === el.tagName) index++;
              return el.tagName.toLowerCase() + ':nth-of-type(' + index + ')';
            };
            const path = [];
            let el = best;
            for (; el && el !== document.documentElement; el = el.parentElement) {
              if (el.id && document.querySelectorAll('#' + CSS.escape(el.id)).length === 1) {
                path.unshift('#' + CSS.escape(el.id)); break;
              }
              path.unshift(step(el));
            }
            if (!el || el === document.documentElement) path.unshift('html');
            const classes = [...best.classList].map((name) => '.' + CSS.escape(name)).join('');
            const like = classes ? best.tagName.toLowerCase() + classes : '';
            return JSON.stringify([location.href, path.join(' > '), like, best.scrollTop, best.scrollLeft]);
          } catch (_) { return null; }
        })()
        """#

    private static func restoreInnerScroll(_ position: String) -> String {
        """
        (() => {
          try {
            const saved = \(position);
            const [href, path, like, top, left] = saved;
            if (location.href !== href) return;
            let done = false, placed = null, timer = 0, stableSince = 0;
            const events = ['wheel', 'keydown', 'mousedown', 'pointerdown', 'touchstart'];
            const stop = () => { done = true; clearInterval(timer); for (const type of events) removeEventListener(type, person, true); };
            const person = (event) => { if (event.isTrusted) stop(); };
            for (const type of events) addEventListener(type, person, true);
            const find = () => {
              try { const element = document.querySelector(path); if (element) return element; } catch (_) {}
              if (like) { try { const matches = document.querySelectorAll(like); if (matches.length === 1) return matches[0]; } catch (_) {} }
              return null;
            };
            const until = Date.now() + 8000;
            const look = () => {
              if (done) return;
              if (Date.now() > until || location.href !== href) return stop();
              const element = find();
              if (!element) return;
              const current = [element.scrollTop, element.scrollLeft];
              if (placed && (current[0] !== placed[0] || current[1] !== placed[1]) && (current[0] || current[1])) return stop();
              if (element.scrollHeight - element.clientHeight < top || element.scrollWidth - element.clientWidth < left) return;
              element.scrollTop = top; element.scrollLeft = left;
              placed = [element.scrollTop, element.scrollLeft];
              if (placed[0] === top && placed[1] === left) {
                if (!stableSince) stableSince = Date.now();
                else if (Date.now() - stableSince > 1500) stop();
              }
            };
            timer = setInterval(look, 100);
            addEventListener('DOMContentLoaded', look);
          } catch (_) {}
        })()
        """
    }

    func recoverIfNeeded() {
        guard needsRecovery else { return }
        needsRecovery = false
        page.reload()
    }

    // MARK: Zoom

    /// Zooms the page and keeps the tab's copy in step, so the address bar's badge updates straight away.
    private func setZoom(_ z: Double) {
        page.zoom = z
        if tab.pageZoom != z { tab.pageZoom = z }
    }

    private static let zoomSteps: [Double] = [0.5, 0.67, 0.75, 0.85, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3]

    func zoom(by direction: Int) {
        let current = page.zoom
        let next: Double
        if direction == 0 {
            next = 1
        } else if direction > 0 {
            next = Self.zoomSteps.first { $0 > current + 0.001 } ?? Self.zoomSteps.last!
        } else {
            next = Self.zoomSteps.last { $0 < current - 0.001 } ?? Self.zoomSteps.first!
        }
        setZoom(next)
        // Private tabs zoom for now only: the saved per-site zoom would record the host.
        if !tab.isPrivate, let host = tab.url?.host() { Preferences.setZoom(next, for: host) }
        window?.showToast(direction == 0 ? "Actual Size" : "Zoom \(Int((next * 100).rounded()))%")
    }

    // MARK: EnginePageDelegate

    func pageDidStartNavigation(_ page: any EnginePage) {
        navigationGeneration &+= 1
        guard let typed = typedRedirectSource else { return }
        typedRedirectSource = typed.started ? nil : (typed.url, typed.at, true)
    }

    func page(_ page: any EnginePage, decide request: NavigationRequest) async -> NavigationDecision {
        guard let library else { return .allow }
        if request.wantsGlance {
            guard let window = library.window(showing: tab) ?? library.activeWindow else { return .allow }
            window.openGlance(request.url, profile: linkPreview?.profile ?? library.browsingProfile(for: tab), source: tab)
            return .cancel
        }
        if request.wantsNewTab {
            if linkPreview != nil, LinkPreviewWindow.supports(request.url) {
                library.showLinkPreview(request.url)
                return .cancel
            }
            library.openInNewTab(request.url, from: tab, foreground: request.wantsForeground)
            return .cancel
        }
        // A new user-initiated navigation supersedes a pending typed address. Redirects arrive
        // as `.other`, so retain the source for that navigation chain.
        if request.isMainFrame {
            switch request.kind {
            case .link, .formSubmit, .backForward, .reload:
                navigationGeneration &+= 1
                typedRedirectSource = nil
            case .other: break
            }
        }
        let scheme = request.url.scheme?.lowercased() ?? ""
        guard ["http", "https", "about", "blob", "data", "file", "javascript", "webkit-extension"].contains(scheme) else {
            // mailto:, zoommtg:, App Store links and the like belong to other apps. Ark asks first (as
            // Chrome does), so a page can't throw you into an app: Zoom's join page fires zoommtg: on its
            // own, and saying no keeps its "join from your browser" option. Email links just open.
            Task { await openInApp(request) }
            return .cancel
        }
        if linkPreview == nil, let window,
           let action = pinnedLinkAction(for: request, currentURL: page.state.url ?? tab.url) {
            switch action {
            case .stayInPin:
                break
            case .today:
                window.newTab(url: request.url, source: .link)
                return .cancel
            case .glance:
                window.openGlance(request.url, profile: library.browsingProfile(for: tab), source: tab)
                return .cancel
            }
        }
        // A call site (or leaving one) moves the tab to the engine it runs on.
        if linkPreview == nil, request.isMainFrame, request.method == "GET", library.needsEngineSwap(self, to: request.url) {
            library.swapEngine(of: tab, to: request.url)
            return .cancel
        }
        if request.isMainFrame, request.method == "GET", let clean = library.cleanedNavigationURL(request.url) {
            return .redirect(clean)
        }
        return .allow
    }

    /// Search-inspired pin-link behavior. Only plain main-frame HTTP(S) clicks qualify; redirects,
    /// forms, modified clicks, same-document fragments, and common authentication routes stay put.
    private func pinnedLinkAction(for request: NavigationRequest, currentURL: URL?) -> PinnedLinkAction? {
        let action = Preferences.pinnedLinkAction
        guard action != .stayInPin, tab.isPinned, request.kind == .link,
              request.isMainFrame, request.method == "GET", !request.wantsNewTab, !request.hasModifiers,
              let scheme = request.url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = request.url.host()?.lowercased() else { return nil }
        if action == .glance {
            guard let currentHost = currentURL?.host()?.lowercased(), currentHost != host else { return nil }
        }
        if let currentURL,
           var current = URLComponents(url: currentURL, resolvingAgainstBaseURL: false),
           var target = URLComponents(url: request.url, resolvingAgainstBaseURL: false) {
            current.fragment = nil
            target.fragment = nil
            if current.url == target.url { return nil }
        }
        let authentication = ["login", "log-in", "log_in", "logon", "signin", "sign-in", "sign_in", "signon",
                             "logout", "log-out", "signout", "sign-out", "auth", "oauth", "oauth2", "sso", "saml", "authorize"]
        let firstHostPart = host.split(separator: ".").first.map(String.init) ?? ""
        if authentication.contains(firstHostPart) || ["accounts", "account", "id", "idp"].contains(firstHostPart) { return nil }
        let pathParts = request.url.path.lowercased().split(separator: "/").map(String.init)
        let isAuthenticationPath = pathParts.contains { part in
            authentication.contains(part) || authentication.contains { part.hasPrefix($0 + ".") }
        }
        return isAuthenticationPath ? nil : action
    }

    /// Hands a link to the app that opens it, asking first, as Safari and Chrome do: a page could
    /// otherwise launch Zoom, FaceTime or the App Store by itself. Always Open and Don't Open are
    /// kept per site and link scheme. A frame inside the page (an ad, an embed) only gets to ask
    /// when it was a click on a link. Email links open straight away.
    private func openInApp(_ request: NavigationRequest) async {
        let url = request.url
        let scheme = url.scheme?.lowercased() ?? ""
        guard request.isMainFrame || request.kind == .link else { return }
        guard let appURL = NSWorkspace.shared.urlForApplication(toOpen: url) else {
            window?.showToast("No app on this Mac opens \(scheme): links")
            return
        }
        // Contact links clicked by the user can open directly; script-driven calls and messages
        // use the site's normal permission prompt instead.
        let clickedContact = ["tel", "facetime", "facetime-audio", "sms"].contains(scheme) && request.kind == .link
        guard scheme != "mailto", !clickedContact, let host = page.state.url?.host() ?? tab.url?.host(), let library else {
            NSWorkspace.shared.open(url)
            return
        }
        switch Self.openAppAnswer(library.sitePermissions(for: host, isPrivate: tab.isPrivate), scheme: scheme) {
        case true?:
            NSWorkspace.shared.open(url)
            return
        case false?:
            if request.kind == .link {
                let app = FileManager.default.displayName(atPath: appURL.path).replacingOccurrences(of: ".app", with: "")
                window?.showToast("\(host) can't open \(app)", actions: [
                    ToastAction(title: "Ask Again") { [weak library] in
                        if let library { Self.setOpenAppAnswer(nil, in: library, host: host, scheme: scheme, isPrivate: self.tab.isPrivate) }
                    }
                ])
            }
            return
        case nil:
            break
        }
        let declineKey = host + " " + scheme
        if request.kind != .link, declinedApps.contains(declineKey) { return }
        guard !askingApps.contains(declineKey) else { return }
        guard let window else { return }
        let app = FileManager.default.displayName(atPath: appURL.path).replacingOccurrences(of: ".app", with: "")
        askingApps.insert(declineKey)
        defer { askingApps.remove(declineKey) }
        let answer = await window.ask(.openApp(app: app, appURL: appURL, host: host), from: tab)
        guard window.currentTab?.id == tab.id else { return }
        if answer == Prompt.alwaysOpen {
            Self.setOpenAppAnswer(true, in: library, host: host, scheme: scheme, isPrivate: tab.isPrivate)
            NSWorkspace.shared.open(url)
        } else if answer == Prompt.neverOpen {
            Self.setOpenAppAnswer(false, in: library, host: host, scheme: scheme, isPrivate: tab.isPrivate)
        } else if answer == .ok {
            NSWorkspace.shared.open(url)
        } else if answer == .cancel, request.kind != .link {
            declinedApps.insert(declineKey)
        }
    }

    /// New saved choices distinguish Don't Open from old negative answers, which meant Not Now.
    private static let openAppPrefix = "open:"
    private static let legacyOpenAppPrefix = "app:"

    static func openAppKey(_ scheme: String) -> String { openAppPrefix + scheme }
    private static func legacyOpenAppKey(_ scheme: String) -> String { legacyOpenAppPrefix + scheme }

    static func setOpenAppAnswer(_ answer: Bool?, in library: Library, host: String, scheme: String, isPrivate: Bool) {
        library.setSitePermission(legacyOpenAppKey(scheme), nil, for: host, isPrivate: isPrivate)
        library.setSitePermission(openAppKey(scheme), answer, for: host, isPrivate: isPrivate)
    }

    /// Always Open (true), Don't Open (false), or ask (nil). Legacy saved yeses remain valid.
    static func openAppAnswer(_ saved: [String: Bool], scheme: String) -> Bool? {
        if let answer = saved[openAppKey(scheme)] { return answer }
        return saved[legacyOpenAppKey(scheme)] == true ? true : nil
    }

    static func openAppAnswers(_ saved: [String: Bool]) -> [String: Bool] {
        var answers: [String: Bool] = [:]
        for (key, value) in saved where key.hasPrefix(legacyOpenAppPrefix) && value {
            answers[String(key.dropFirst(legacyOpenAppPrefix.count))] = true
        }
        for (key, value) in saved where key.hasPrefix(openAppPrefix) {
            answers[String(key.dropFirst(openAppPrefix.count))] = value
        }
        return answers
    }

    static func isOpenAppKey(_ key: String) -> Bool {
        key.hasPrefix(openAppPrefix) || key.hasPrefix(legacyOpenAppPrefix)
    }

    static func appName(forScheme scheme: String) -> String {
        guard let url = URL(string: scheme + "://"),
              let appURL = NSWorkspace.shared.urlForApplication(toOpen: url) else { return scheme + ": links" }
        return FileManager.default.displayName(atPath: appURL.path).replacingOccurrences(of: ".app", with: "")
    }

    func page(_ page: any EnginePage, didCommit url: URL?) {
        tab.loadError = nil
        library?.windows.forEach { $0.cancelPrompts(for: tab.id) }
        if let position = pendingInnerScrollRestore {
            pendingInnerScrollRestore = nil
            library?.discardSleepingScrollState(for: tab.id)
            Task { _ = try? await page.evaluate(Self.restoreInnerScroll(position), inWorld: "page") }
        }
        if let host = url?.host() {
            let z = Preferences.zoom(for: host)
            if abs(page.zoom - z) > 0.001 { setZoom(z) }
        }
        guard let library, !library.agents.isInAgentSpace(tab), let host = SiteStyles.host(of: url),
              let view = page.view as? WKWebView else { return }
        let styles = tab.isPrivate ? library.privateSiteShapes[tab.id] : library.siteStyles
        guard let styles, styles.hasStyle(for: host) else { return }
        Task { await styles.apply(to: view, on: host) }
    }

    func page(_ page: any EnginePage, didFinish url: URL, title: String) {
        library?.scheduleSave()
        let typed = typedRedirectSource
        typedRedirectSource = nil
        guard !tab.isPrivate, let library else { pendingSource = nil; return }
        let profileID = (page.view as? WKWebView)?.configuration.websiteDataStore.identifier
        let history = library.profileHistory.store(for: profileID)
        let source = pendingSource ?? .link
        let mayRecordTyped = !library.agents.isInAgentSpace(tab)
        pendingSource = nil
        Task {
            await history.recordVisit(url: url, title: title, source: source)
            if mayRecordTyped, let typed, Date().timeIntervalSince(typed.at) < 30,
               typed.url.host()?.lowercased() != url.host()?.lowercased() {
                await history.recordVisit(url: typed.url, title: title, source: .typed)
            }
        }
    }

    func page(_ page: any EnginePage, didFailWith error: NSError) {
        typedRedirectSource = nil
        let failed = (error.userInfo[NSURLErrorFailingURLErrorKey] as? URL) ?? page.state.url
        tab.loadError = LoadError(url: failed, error: error)
    }

    func page(_ page: any EnginePage, trusts certificate: ServerCertificate) -> Bool {
        guard let library else { return false }
        if tab.isPrivate {
            return library.privateCertificateExceptions[certificate.site] == certificate.fingerprint
        }
        return library.settings.certificateExceptions[certificate.site] == certificate.fingerprint
    }

    /// Trust only the exact leaf certificate shown on this error page, then retry its URL.
    func visitAnyway() {
        guard let error = tab.loadError, let fingerprint = error.certificateFingerprint,
              let url = error.url, let host = url.host(), let library else { return }
        let site = ServerCertificate.site(host: host, port: url.port)
        if tab.isPrivate {
            library.privateCertificateExceptions[site] = fingerprint
        } else {
            library.settings.certificateExceptions[site] = fingerprint
        }
        load(url, source: .typed)
    }

    func pageContentProcessDidTerminate(_ page: any EnginePage) {
        guard window != nil else { needsRecovery = true; return }
        // Dying again straight after a reload is the page itself; reloading would loop.
        let diedRecently = lastTermination.map { Date().timeIntervalSince($0) < 10 } ?? false
        lastTermination = .now
        if diedRecently {
            tab.loadError = LoadError(url: tab.url, error: NSError(domain: "Ark", code: 1,
                                                                   userInfo: [NSLocalizedDescriptionKey: "This page keeps crashing."]))
        } else {
            page.reload()
        }
    }

    func page(_ page: any EnginePage, openedPopup popup: any EnginePage, url: URL?) -> (any EnginePageDelegate)? {
        guard let library else { return nil }
        if let linkPreview { return library.showLinkPreview(url, popup: popup, from: linkPreview).controller }
        return library.openPopup(from: tab, page: popup, url: url)
    }

    func pageDidRequestClose(_ page: any EnginePage) {
        if let linkPreview { linkPreview.close() } else { library?.close(tab) }
    }

    func pageWillReturnFromPictureInPicture(_ page: any EnginePage) {
        guard page === self.page, let library else { return }
        if let browser = library.window(showing: tab) ?? library.owner(of: tab) ?? library.activeWindow {
            browser.select(tab)
            browser.nsWindow?.makeKeyAndOrderFront(nil)
        } else {
            library.openWindow(.tab(tab))
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func page(_ page: any EnginePage, show dialog: EngineDialog) async -> EngineDialogResponse {
        guard let window else { return .cancel }
        return await window.ask(.dialog(dialog), from: tab)
    }

    func page(_ page: any EnginePage, requestPermission permission: EnginePermission, host: String) async -> Bool {
        guard let library else { return false }
        // Screen sharing is asked every time, like other browsers do.
        let remembers = permission != .screen
        if remembers, let saved = library.sitePermissions(for: host, isPrivate: tab.isPrivate)[permission.rawValue] { return saved }
        guard let window else { return false }
        let answer = await window.ask(.permission(permission, host: host), from: tab)
        // Cancelled because the tab went away: don't remember a "no" the user never gave.
        guard answer != .cancel || window.currentTab?.id == tab.id else { return false }
        let granted = answer == .ok
        // A private tab's answer lasts until the private space closes, and isn't saved.
        if remembers { library.setSitePermission(permission.rawValue, granted, for: host, isPrivate: tab.isPrivate) }
        return granted
    }

    func page(_ page: any EnginePage, chooseFiles request: FileChooserRequest) async -> [URL]? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = request.allowsMultiple
        panel.canChooseDirectories = request.allowsDirectories
        panel.canChooseFiles = true
        if let window = page.view.window ?? NSApp.keyWindow {
            return await panel.beginSheetModal(for: window) == .OK ? panel.urls : nil
        }
        return panel.runModal() == .OK ? panel.urls : nil
    }

    func page(_ page: any EnginePage, didStartDownload download: EngineDownload) {
        guard let library else { return }
        library.downloads.insert(download, at: 0)
        (window ?? library.activeWindow)?.showToast("Downloading \(download.filename)")
    }

    func pageDidDeclineCookieBanner(_ page: any EnginePage) {
        guard let browser = window, let url = page.state.url,
              browser.lastCookieToastURL != url else { return }
        browser.lastCookieToastURL = url
        browser.showToast("Cookie banner declined")
    }
}
