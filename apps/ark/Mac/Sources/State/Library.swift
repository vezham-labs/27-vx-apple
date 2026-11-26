import AppKit
import Observation
import BrowserCore
import BrowserEngine
import WebKitEngine
import Suggest
import Extensibility
import os

private let windowLog = Logger(subsystem: "app.vezham.ark", category: "windows")

/// Everything the windows share: spaces, tabs, favourites, settings, live pages and downloads.
/// Each window is a `Browser` looking into it with its own space and tab.
///
/// Engine-neutral: pages come from `engine`, and nothing here knows it's WebKit.
@MainActor @Observable
final class Library {
    var spaces: [Space]
    /// Temporary developer preference; private-tab choices are kept separately and never saved.
    var reloadWithoutCacheHosts: Set<String> = []
    var privateReloadWithoutCacheSites: Set<String> = []
    /// Saved sites scoped to each website profile, like Search's bookmark stores.
    var favoritesByProfile: [String: [Favorite]]
    var archive: [BrowserTab] = []
    var settings = BrowserSettings() {
        didSet {
            guard settings != oldValue else { return }
            if settings.blockContent != oldValue.blockContent || settings.filterGroups != oldValue.filterGroups
                || settings.declineCookieBanners != oldValue.declineCookieBanners
                || settings.blockingDisabledHosts != oldValue.blockingDisabledHosts {
                applyBlocking()
            }
            if !isApplyingSync { scheduleSave() }
        }
    }
    /// Sends the Global Privacy Control signal (`navigator.globalPrivacyControl`) to every site.
    var globalPrivacyControl: Bool { didSet { Preferences.globalPrivacyControl = globalPrivacyControl; applyBlocking() } }
    /// Forget history, cookies and site data when Ark quits.
    var clearDataOnQuit: Bool { didSet { Preferences.clearDataOnQuit = clearDataOnQuit } }
    /// Inspect Element on every page.
    var developerTools: Bool {
        didSet { Preferences.developerTools = developerTools; engine.developerToolsEnabled = developerTools }
    }
    /// Safari web extensions installed on this Mac, run in every page.
    var useSafariExtensions: Bool {
        didSet { Preferences.useSafariExtensions = useSafariExtensions; reloadExtensions() }
    }
    /// Settings › Audio. Live: pages in a call pick changes up within a second.
    var callAudio: CallAudioTuning {
        didSet { Preferences.callAudio = callAudio; (engine as? CallAudioConfigurable)?.callAudio = callAudio }
    }
    /// The latest numbers from a page in a call, for the Audio settings readout.
    var callAudioStats: CallAudioStats?
    /// The extensions running now, for the toolbar.
    private(set) var extensions: [EngineExtension] = []
    var shownExtensionPanels: [String: URL] = [:]
    /// Bumped when pins change or an extension updates its action, so the address pill redraws.
    var extensionPinsRevision = 0
    var extensionActionsRevision = 0
    /// Extensions added from the Chrome Web Store, Firefox Add-ons or a folder (Safari ones come from apps).
    let extensionCatalog: ExtensionCatalog
    @ObservationIgnored let extensionInstaller: ExtensionInstaller
    /// Notes pinned to pages, which agents read too.
    let margin: MarginStore
    /// Every tool that plugs into the window: the right panel, sidebar sections, command bar rows.
    let workbench = Workbench()
    /// Coding agents over MCP. Made after everything else, since it reaches back into the library.
    @ObservationIgnored private(set) var agents: AgentBridge!
    var downloads: [EngineDownload] = []
    /// Permission answers given in private tabs, by host. Kept in memory and dropped with the private space.
    @ObservationIgnored var privatePermissions: [String: [String: Bool]] = [:]
    /// Exact certificate approvals made in private tabs; never persisted.
    @ObservationIgnored var privateCertificateExceptions: [String: String] = [:]
    var filterStatus = FilterStatus()
    /// Tabs closed this session, newest last, for Shift-Cmd-T. Never private tabs.
    private(set) var recentlyClosed: [BrowserTab] = []
    /// The open windows, most recently active first.
    private(set) var windows: [Browser] = []
    /// Open windows, oldest first. The oldest one lists Today tabs that no open window owns.
    private(set) var windowsByAge: [Browser] = []
    /// Set once quitting is under way, so the windows going away keep their tabs for next time.
    @ObservationIgnored var isTerminating = false

    let engine: any BrowserEngine
    /// Which engine a tab's page uses for a URL: `engine` (WebKit) unless something else is set up.
    /// The full Ark build sets this for call tabs (Meet, Zoom, Teams run on Chromium).
    @ObservationIgnored var engineChooser: ((BrowserTab, URL?) -> any BrowserEngine)?
    /// Asked before a tab closes; false keeps it open (a call tab asks "Leave the call?").
    @ObservationIgnored var closeGuard: ((BrowserTab) -> Bool)?
    /// Bumped when a tab's page moves to another engine, so views show the new page.
    private(set) var pageSwaps = 0
    /// The call floating in its own window while you're on other tabs (`CallPiP`), and the calls you closed
    /// that window for (the capsule leads back to them instead).
    var pipTabID: UUID?
    var pipClosedFor: Set<UUID> = []
    @ObservationIgnored let videoPictureInPicture = VideoPictureInPicture()
    @ObservationIgnored let videoMiniPlayer = VideoMiniPlayer()
    let history: HistoryStore
    let profileHistory: ProfileHistoryStores
    @ObservationIgnored private let suggestionSeeds = SeedProvider.bundled()
    @ObservationIgnored let siteStyles: SiteStyles
    /// Temporary presentation edits for individual private tabs; never persisted.
    @ObservationIgnored var privateSiteShapes: [UUID: SiteStyles] = [:]
    /// Local Mac canvases; intentionally not part of browser sync yet.
    let easels: EaselStore
    /// Live pages, by tab. The least recently used are unloaded past `capacity`.
    @ObservationIgnored private(set) var controllers: [UUID: TabController] = [:]
    @ObservationIgnored private var lru: [UUID] = []
    /// Inner scroll positions for pages unloaded to save memory. Kept only for open tabs.
    @ObservationIgnored private var sleepingScrollStates: [UUID: String] = [:]
    @ObservationIgnored private let capacity = 24
    @ObservationIgnored private let snapshotURL: URL?
    let syncCoordinator: BrowserSyncCoordinator
    @ObservationIgnored private var isApplyingSync = false
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var blockingTask: Task<Void, Never>?
    @ObservationIgnored private var idlePageTask: Task<Void, Never>?
    @ObservationIgnored private var memoryPressureSource: DispatchSourceMemoryPressure?
    @ObservationIgnored private var unloadCompletions: [UUID: [@MainActor () -> Void]] = [:]
    /// Kept so state written by the iPhone format round-trips; the Mac doesn't show Saved yet.
    @ObservationIgnored private var savedSites: [SavedSite] = []
    /// The space the first window opens on.
    @ObservationIgnored private(set) var launchSpaceID: UUID

    init(engine: any BrowserEngine,
         history: HistoryStore = HistoryStore(fileURL: HistoryStore.defaultFileURL()),
         snapshotURL: URL? = Library.defaultSnapshotURL()) {
        self.engine = engine
        engine.linkPreviewModifier = Preferences.linkPreviewModifier
        self.history = history
        profileHistory = ProfileHistoryStores(defaultStore: history)
        self.snapshotURL = snapshotURL
        syncCoordinator = BrowserSyncCoordinator(
            configurationURL: snapshotURL?.deletingLastPathComponent().appending(path: "sync-folder.json"))
        globalPrivacyControl = Preferences.globalPrivacyControl
        clearDataOnQuit = Preferences.clearDataOnQuit
        developerTools = Preferences.developerTools
        useSafariExtensions = Preferences.useSafariExtensions
        callAudio = Preferences.callAudio
        (engine as? WebKitEngine)?.videoKeyControls = Preferences.videoKeyControls
        let support = snapshotURL?.deletingLastPathComponent()
        siteStyles = SiteStyles(fileURL: support?.appending(path: "site-styles.json"))
        easels = EaselStore(fileURL: (support ?? FileManager.default.temporaryDirectory).appending(path: "easels.json"))
        extensionCatalog = ExtensionCatalog(fileURL: support?.appending(path: "extensions.json"))
        extensionInstaller = ExtensionInstaller(
            root: (support ?? FileManager.default.temporaryDirectory).appending(path: "Extensions"),
            fetch: Library.fetch, unzip: Library.unzip, fetchRequest: Library.fetchRequest)
        margin = MarginStore(fileURL: support?.appending(path: "margin.json"))
        if let snapshotURL, let data = try? Data(contentsOf: snapshotURL),
           let snap = try? JSONDecoder().decode(BrowserSnapshot.self, from: data), !snap.spaces.isEmpty {
            spaces = snap.spaces.map(Space.init)
            launchSpaceID = snap.selectedSpaceID ?? snap.spaces[0].id
            favoritesByProfile = snap.profileFavorites ?? [FavoriteProfileKey.default: snap.favorites]
            archive = snap.archive.map(BrowserTab.init)
            savedSites = snap.saved ?? []
            if let s = snap.settings { settings = s }
        } else {
            let personal = Space(name: "Personal", symbol: "house.fill", colorIndex: 0)
            spaces = [personal, Space(name: "Work", symbol: "briefcase.fill", colorIndex: 1)]
            launchSpaceID = personal.id
            favoritesByProfile = [FavoriteProfileKey.default: Self.starterFavorites]
        }
        engine.developerToolsEnabled = developerTools
        if let calls = engine as? CallAudioConfigurable {
            calls.callAudio = callAudio
            calls.onCallAudioStats = { [weak self] in self?.callAudioStats = $0 }
        }
        applyBlocking()
        engine.extensionHost = self
        reloadExtensions()
        agents = AgentBridge(library: self)
        BuiltInTools.register(in: workbench)
        SpaceRouter.register(in: workbench, library: self)
        NotesUI.installPageMenu(library: self)
        #if !SPIKE
        // SpikeArk sets mock servers instead. Radar only looks at this Mac's ports while it's on
        // (it's in the Agent Pack, off for new installs).
        if workbench.isEnabled("radar") { startRadar() }
        workbench.onEnabledChange = { [weak self] id, on in
            guard id == "radar" else { return }
            if on { self?.startRadar() } else { RadarStore.shared.stopLive() }
        }
        #endif
    }

    #if !SPIKE
    private func startRadar() {
        RadarStore.shared.startLive(library: self, ownPorts: [Int(AgentBridge.port)])
    }
    #endif

    func reloadExtensions() {
        engine.unloadExtensions()
        extensions = []
        BuiltInTools.sync(extensions: [], in: workbench)
        guard engine.info.capabilities.contains(.webExtensions) else { return }
        let folders = extensionFolders()
        guard useSafariExtensions || !folders.isEmpty else { return }
        Task {
            // Extensions expect a browser window to exist when they start (chrome.windows.getCurrent).
            while windows.isEmpty { try? await Task.sleep(for: .milliseconds(100)) }
            // What couldn't load is in the engine's log.
            _ = await engine.loadInstalledExtensions(folders: folders, includeApps: useSafariExtensions)
            extensions = engine.extensions
            BuiltInTools.sync(extensions: extensions, in: workbench)
        }
    }

    private static let starterFavorites: [Favorite] = [
        ("https://www.youtube.com", "YouTube"), ("https://github.com", "GitHub"),
        ("https://en.wikipedia.org", "Wikipedia"), ("https://www.apple.com", "Apple"),
    ].enumerated().map { i, f in Favorite(url: URL(string: f.0)!, title: f.1, order: i) }

    static func defaultSnapshotURL() -> URL {
        AppFolders.support.appending(path: "Browser/state.json")
    }

    // MARK: Windows

    func register(_ window: Browser) {
        videoPictureInPicture.registerWindow(window)
        windows.removeAll { $0 === window }
        windows.insert(window, at: 0)
        if !windowsByAge.contains(where: { $0 === window }) { windowsByAge.append(window) }
        startIdlePageEviction()
    }

    func unregister(_ window: Browser) {
        // AppKit's close and SwiftUI's onDisappear both land here; the first one counts.
        guard windowsByAge.contains(where: { $0 === window }) else { return }
        videoPictureInPicture.unregisterWindow(window)
        windows.removeAll { $0 === window }
        windowsByAge.removeAll { $0 === window }
        if let observer = window.closeObserver { NotificationCenter.default.removeObserver(observer) }
        window.closeObserver = nil
        // Closing one of several windows archives its Today tabs, like Arc. The last window's tabs,
        // and every window's when quitting, stay put for the next window to pick up.
        if !windows.isEmpty, !isTerminating {
            let count = archiveTabs(of: window)
            windowLog.debug("Closed a window: \(count) tabs to the archive")
        } else if windows.isEmpty, !isTerminating {
            Task { [weak self] in await self?.unloadIdlePages(after: 0) }
        }
        scheduleSave()
    }

    private func startIdlePageEviction() {
        guard idlePageTask == nil else { return }
        idlePageTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard let self else { return }
                await self.unloadIdlePages()
            }
        }
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let pressure = self.memoryPressureSource?.data ?? []
            let idle = pressure.contains(.critical) ? 0.0 : 5.0 * 60
            Task { @MainActor [weak self] in await self?.unloadIdlePages(after: idle) }
        }
        memoryPressureSource = source
        source.resume()
    }

    /// Release inactive WebViews without interrupting work the user expects to continue.
    /// Re-selecting a tab rebuilds its page from the saved WebKit session state.
    func unloadIdlePages(after override: TimeInterval? = nil, now: Date = .now) async {
        let configured = min(12.0 * 60 * 60, max(0.0, settings.unloadIdlePagesAfterMinutes * 60))
        guard override != nil || configured > 0 else { return }
        let wait = max(0, override ?? configured)
        let visible = Set(windows.flatMap(\.visibleTabIDs))
        let activeDownload = downloads.contains { $0.status == .running }
        let candidates = lru.sorted { id1, id2 in
            (tab(id: id1)?.lastActive ?? .distantFuture) < (tab(id: id2)?.lastActive ?? .distantFuture)
        }
        for id in candidates {
            guard let tab = tab(id: id), !tab.isPrivate, tab.call == nil,
                  now.timeIntervalSince(tab.lastActive) >= wait,
                  !visible.contains(id), videoMiniPlayer.tabID != id,
                  !videoPictureInPicture.isFloating(id), !agents.isInAgentSpace(tab),
                  !activeDownload,
                  !windows.contains(where: { $0.activePrompt?.tabID == id }),
                  let controller = controllers[id], controller.engineID == engine.info.id,
                  !controller.page.state.isLoading, !controller.page.state.isBusy else { continue }

            // Sound, form state, calls, and loads are represented in PageState. This also
            // protects muted video, WebKit PiP, and audio elements WebKit doesn't report as audible.
            guard let mediaActive = try? await controller.page.evaluate("""
                return Boolean(document.pictureInPictureElement)
                    || [...document.querySelectorAll('video, audio')].some(media =>
                        (!media.paused && !media.ended)
                        || media.webkitPresentationMode === 'picture-in-picture');
                """, inWorld: "ark.idle-page-check") as? Bool, !mediaActive else { continue }

            guard controllers[id] === controller,
                  now.timeIntervalSince(tab.lastActive) >= wait,
                  !windows.flatMap(\.visibleTabIDs).contains(id),
                  !controller.page.state.isLoading, !controller.page.state.isBusy else { continue }
            unload(id)
        }
    }

    /// The window that lists a Today tab: the one it belongs to, or the oldest window when that
    /// one isn't open (or the tab predates per-window tabs). Pinned and favourite tabs show in every window.
    func owner(of tab: BrowserTab) -> Browser? {
        if let key = tab.windowKey, let w = windowsByAge.first(where: { $0.windowKey == key }) { return w }
        return windowsByAge.first
    }

    /// Whether a tab belongs to another window that's open right now.
    func isOwnedElsewhere(_ tab: BrowserTab, than window: Browser) -> Bool {
        guard !tab.isPinned, tab.favoriteID == nil, let key = tab.windowKey, key != window.windowKey else { return false }
        return windowsByAge.contains { $0.windowKey == key }
    }

    /// A closed window's Today tabs go to the archive (private ones just close).
    @discardableResult
    private func archiveTabs(of window: Browser) -> Int {
        var count = 0
        for space in spaces {
            let leaving = space.today.filter { $0.favoriteID == nil && $0.windowKey == window.windowKey }
            guard !leaving.isEmpty else { continue }
            for tab in leaving where tab.isPrivate { close(tab) }
            let kept = leaving.filter { !$0.isPrivate }
            space.today.removeAll { t in kept.contains { $0.id == t.id } }
            if let id = space.selectedTabID, kept.contains(where: { $0.id == id }) { space.selectedTabID = nil }
            for tab in kept {
                unload(tab.id)
                tab.websiteSessionProfileID = space.websiteProfileID
                tab.windowKey = nil
            }
            archive.insert(contentsOf: kept.filter { $0.url != nil }, at: 0)
            count += kept.count
        }
        archive = Array(archive.prefix(500))
        return count
    }

    /// The window someone's using, for things that arrive from outside (links, downloads).
    var activeWindow: Browser? {
        windows.first { $0.nsWindow?.isKeyWindow == true } ?? windows.first
    }

    func markActive(_ window: Browser) {
        guard windows.first !== window else { return }
        register(window)
    }

    /// The window showing a tab right now, if any. A tab is on screen in one window at most.
    func window(showing tab: BrowserTab) -> Browser? {
        windows.first { $0.isShowing(tab.id) }
    }

    /// Opens a window through SwiftUI. Set by the first window that appears.
    @ObservationIgnored var openWindowAction: (() -> Void)?
    /// Opens (or brings forward) the Settings window. Set by the first browser window.
    @ObservationIgnored var openSettingsAction: (() -> Void)?

    /// Opens Settings, on a given pane ("spaces", "agents"…) if asked.
    func openSettings(pane: String? = nil) {
        if let pane { UserDefaults.standard.set(pane, forKey: "settingsTab") }
        openSettingsAction?()
        NSApp.activate()
    }
    @ObservationIgnored private var windowRequests: [WindowRequest] = []
    @ObservationIgnored var linkWindows: [UUID: LinkPreviewWindow] = [:]
    var needsFirstWindow: Bool { openWindowAction == nil && !windowRequests.isEmpty }

    /// Opens a new window, showing `request` (or a new-tab command bar).
    func openWindow(_ request: WindowRequest? = nil) {
        if let request { windowRequests.append(request) }
        openWindowAction?()
    }

    /// What the window being made should show first.
    func takeWindowRequest() -> WindowRequest? {
        windowRequests.isEmpty ? nil : windowRequests.removeFirst()
    }

    /// A link from another app, in the window in use, or a new one when none is open.
    func openExternal(_ url: URL, sourceApp: String? = nil, inLinkWindow: Bool = Preferences.externalLinksInPreview) {
        let hasExplicitRoute = SpaceRouter.shared.externalSpace(for: url, sourceApp: sourceApp, in: regularSpaces) != nil
        if !hasExplicitRoute, Preferences.externalLinksFindExistingTab, url.host() != nil,
           ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            if let preview = linkWindows.values.first(where: { Self.sameExternalPage(url, $0.tab.url) }) {
                preview.showWindow(nil)
                activateForIncomingLink()
                return
            }
            for window in windows {
                guard !window.currentSpace.isPrivate,
                      let tab = window.currentSpace.allTabs.first(where: {
                          window.lists($0) && !$0.isPrivate && Self.sameExternalPage(url, $0.url)
                      }) else { continue }
                window.select(tab)
                window.nsWindow?.makeKeyAndOrderFront(nil)
                activateForIncomingLink()
                return
            }
        }
        let window = activeWindow
        let opensPreview = inLinkWindow && LinkPreviewWindow.supports(url)
        let launchSpace = window == nil && !opensPreview ? regularSpaces.first { $0.id == launchSpaceID } : nil
        let target = externalLinkDestination(for: url, sourceApp: sourceApp, fallback: launchSpace)
        if opensPreview {
            showLinkPreview(url, destination: target)
            return
        }
        if let window {
            window.commandBar = nil
            window.newTab(url: url, in: target, source: .link)
            window.nsWindow?.makeKeyAndOrderFront(nil)
            activateForIncomingLink()
        } else {
            openWindow(.externalLink(url, spaceID: target.id))
        }
    }

    /// Search's incoming-link behavior compares the complete address, ignoring only trailing slashes.
    private static func sameExternalPage(_ one: URL, _ other: URL?) -> Bool {
        guard var other = other?.absoluteString else { return false }
        var one = one.absoluteString
        while one.hasSuffix("/") { one.removeLast() }
        while other.hasSuffix("/") { other.removeLast() }
        return one == other
    }

    @discardableResult
    func showLinkPreview(_ url: URL?, popup: (any EnginePage)? = nil, from parent: LinkPreviewWindow? = nil,
                         destination: Space? = nil) -> LinkPreviewWindow {
        let preview = LinkPreviewWindow(url: url, library: self, popup: popup, parent: parent,
                                        target: destination ?? externalLinkDestination(for: url))
        if let last = linkWindows.values.first(where: { $0.window?.isKeyWindow == true }),
           let position = last.window?.frame.origin {
            preview.window?.setFrameOrigin(NSPoint(x: position.x + 20, y: position.y - 20))
        }
        linkWindows[preview.tab.id] = preview
        preview.showWindow(nil)
        activateForIncomingLink()
        return preview
    }

    /// An external link can arrive while another app is frontmost. On macOS
    /// 14+, retry activation only if the normal request did not bring Ark up.
    private func activateForIncomingLink() {
        if #available(macOS 14, *) {
            NSApp.activate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                guard !NSApp.isActive else { return }
                NSApp.activate(ignoringOtherApps: true)
            }
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func externalLinkDestination(for url: URL?, sourceApp: String? = nil, fallback: Space? = nil) -> Space {
        let routed = SpaceRouter.shared.externalSpace(for: url, sourceApp: sourceApp, in: regularSpaces)
            ?? regularSpaces.first { $0.id == settings.externalLinksSpaceID }
        return routed ?? activeWindow.flatMap { $0.currentSpace.isPrivate ? nil : $0.currentSpace } ?? fallback ?? regularSpaces[0]
    }

    func keepLinkPreview(_ controller: TabController, destination: UUID, profile: BrowsingProfile) {
        let tab = controller.tab
        let window = activeWindow
        let target = regularSpaces.first { $0.id == destination }
            ?? window.flatMap { $0.currentSpace.isPrivate ? nil : $0.currentSpace }
            ?? regularSpaces[0]
        tab.windowKey = window?.windowKey
        target.today.insert(tab, at: 0)
        if browsingProfile(in: target) == profile {
            adopt(controller)
        } else {
            controller.page.close()
            tab.interactionState = nil
        }
        if let window {
            window.commandBar = nil
            window.select(tab)
            window.nsWindow?.makeKeyAndOrderFront(nil)
        } else {
            openWindow(.tab(tab))
            if needsFirstWindow { AppDelegate.askForFirstWindow() }
        }
        scheduleSave()
    }

    func window(for nsWindow: NSWindow?) -> Browser? {
        guard let nsWindow else { return nil }
        return windows.first { $0.nsWindow === nsWindow }
    }

    // MARK: Lookup

    var regularSpaces: [Space] { spaces.filter { !$0.isPrivate } }
    var privateSpace: Space? { spaces.first { $0.isPrivate } }
    var allTabs: [BrowserTab] { spaces.flatMap(\.allTabs) }

    func space(containing tab: BrowserTab) -> Space? {
        spaces.first { $0.allTabs.contains { $0.id == tab.id } }
    }

    func tab(id: UUID) -> BrowserTab? { allTabs.first { $0.id == id } }

    // MARK: Pages

    func browsingProfile(in space: Space?) -> BrowsingProfile {
        if space?.isPrivate == true { return .ephemeral }
        return space?.websiteProfileID.map(BrowsingProfile.named) ?? .standard
    }

    func websiteProfileName(for space: Space) -> String? {
        guard let profileID = space.websiteProfileID else { return nil }
        return settings.websiteProfiles.first { $0.id == profileID }?.name
    }

    func browsingProfile(for tab: BrowserTab) -> BrowsingProfile {
        tab.isPrivate ? .ephemeral : browsingProfile(in: space(containing: tab))
    }

    func assignWebsiteProfile(_ id: UUID?, to space: Space) {
        guard !space.isPrivate, space.id != Preferences.agentSpaceID, space.websiteProfileID != id,
              id.map({ id in settings.websiteProfiles.contains { $0.id == id } }) ?? true else { return }
        for tab in space.allTabs { resetBrowsingSession(of: tab) }
        for window in windows where window.selectedSpaceID == space.id {
            window.closeGlance()
            window.reader = nil
            window.commandBar = nil
        }
        space.clearGitHubFoldersForProfileChange()
        space.websiteProfileID = id
        pageSwaps += 1
        scheduleSave()
    }

    func renameWebsiteProfile(_ id: UUID, to name: String) {
        guard let index = settings.websiteProfiles.firstIndex(where: { $0.id == id }) else { return }
        var profile = settings.websiteProfiles[index]
        guard profile.rename(to: name) else { return }
        settings.websiteProfiles[index] = profile
        scheduleSave()
    }

    func deleteWebsiteProfile(_ id: UUID) async {
        guard settings.websiteProfiles.contains(where: { $0.id == id }) else { return }
        let affectedSpaces = regularSpaces.filter { $0.websiteProfileID == id }
        let affectedTabs = affectedSpaces.flatMap(\.allTabs)
        for space in affectedSpaces {
            assignWebsiteProfile(nil, to: space)
        }
        for tab in affectedTabs { await unloadAndWait(tab.id) }
        for tab in affectedTabs {
            tab.interactionState = nil
            tab.websiteSessionProfileID = nil
        }
        archive.removeAll { $0.websiteSessionProfileID == id }
        recentlyClosed.removeAll { $0.websiteSessionProfileID == id }
        favoritesByProfile.removeValue(forKey: FavoriteProfileKey.key(for: id))
        settings.websiteProfiles.removeAll { $0.id == id }
        await engine.deleteWebsiteDataStore(for: .named(id))
        await profileHistory.deleteProfile(id)
        scheduleSave()
    }

    private func resetBrowsingSession(of tab: BrowserTab) {
        for window in windows { window.cancelPrompts(for: tab.id) }
        controllers[tab.id]?.discardInnerScrollState()
        sleepingScrollStates[tab.id] = nil
        // Profile changes must never keep presenting the old WebView after its asynchronous
        // PiP/session cleanup completes. The immediate page swap handles the common case;
        // this second one makes the view resolve the newly configured controller afterwards.
        unload(tab.id) { [weak self, weak tab] in
            // `finishUnload` snapshots the former WebView just before it closes. It may have
            // written the old profile ID back while this reset was waiting for PiP cleanup.
            tab?.interactionState = nil
            tab?.websiteSessionProfileID = nil
            self?.pageSwaps += 1
        }
        tab.interactionState = nil
        tab.websiteSessionProfileID = nil
        tab.loadError = nil
    }

    /// The live page for a tab, made (and restored) on first use.
    func controller(for tab: BrowserTab) -> TabController {
        _ = pageSwaps
        touch(tab.id)
        if let c = controllers[tab.id] { return c }
        let native = Welcome.isWelcome(tab.url) || LibraryPage.isLibrary(tab.url)
        let pageEngine = native ? engine : engine(for: tab, url: tab.url)
        if tab.websiteSessionProfileID != space(containing: tab)?.websiteProfileID {
            tab.interactionState = nil
        }
        let c = TabController(tab: tab, library: self, engineID: pageEngine.info.id) { delegate in
            pageEngine.makePage(options: PageOptions(profile: browsingProfile(for: tab),
                                                 // The welcome tab is native; its page starts blank.
                                                 url: Welcome.isWelcome(tab.url) || LibraryPage.isLibrary(tab.url) ? nil : tab.url,
                                                 sessionState: tab.interactionState),
                            delegate: delegate)
        }
        if let state = sleepingScrollStates[tab.id] { c.restoreInnerScroll(state) }
        controllers[tab.id] = c
        evictIfNeeded(keeping: tab.id)
        return c
    }

    func existingController(for tab: BrowserTab) -> TabController? { controllers[tab.id] }

    func discardSleepingScrollState(for tabID: UUID) {
        sleepingScrollStates[tabID] = nil
    }

    func cleanedNavigationURL(_ url: URL) -> URL? {
        guard settings.cleanLinks, !settings.blockingDisabled(for: url.host()) else { return nil }
        return LinkCleaner.clean(url)
    }

    func engine(for tab: BrowserTab, url: URL?) -> any BrowserEngine {
        if case .named = browsingProfile(for: tab) { return engine }
        return engineChooser?(tab, url) ?? engine
    }

    /// Whether going to `url` means the tab's page has to move to another engine.
    func needsEngineSwap(_ controller: TabController, to url: URL) -> Bool {
        engine(for: controller.tab, url: url).info.id != controller.engineID
    }

    /// Moves a tab's page to the engine `url` belongs on, and loads `url` there. The old page goes.
    func swapEngine(of tab: BrowserTab, to url: URL, source: Frecency.VisitSource = .link, rememberTypedAddress: Bool = false) {
        guard let original = controllers[tab.id] else { return }
        let generation = original.navigationGeneration
        let target = engine(for: tab, url: url)
        videoPictureInPicture.beforeTabUnload(tab.id) { [weak self] in
            guard let self else { return }
            self.videoMiniPlayer.beforeTabUnload(tab.id) {
                guard self.space(containing: tab) != nil, self.controllers[tab.id] === original,
                      original.navigationGeneration == generation else { return }
                self.finishEngineSwap(of: tab, to: url, using: target, source: source, rememberTypedAddress: rememberTypedAddress)
            }
        }
    }

    private func finishEngineSwap(of tab: BrowserTab, to url: URL, using target: any BrowserEngine,
                                  source: Frecency.VisitSource, rememberTypedAddress: Bool) {
        if let old = controllers[tab.id] {
            old.page.close()
            controllers[tab.id] = nil
            tab.call = nil
        }
        tab.interactionState = nil
        let c = TabController(tab: tab, library: self, engineID: target.info.id) { delegate in
            target.makePage(options: PageOptions(profile: browsingProfile(for: tab)), delegate: delegate)
        }
        controllers[tab.id] = c
        touch(tab.id)
        c.load(url, source: source, rememberTypedAddress: rememberTypedAddress)
        pageSwaps += 1
    }

    private func adopt(_ controller: TabController) {
        controllers[controller.tab.id] = controller
        touch(controller.tab.id)
        evictIfNeeded(keeping: controller.tab.id)
    }

    private func touch(_ id: UUID) {
        lru.removeAll { $0 == id }
        lru.append(id)
    }

    /// Unloads the least recently used pages past `capacity`. Never one on screen, and never one
    /// that's busy: a call, music or a half-written message would be lost, so those stay loaded
    /// even if that means more than `capacity` live pages for a while.
    private func evictIfNeeded(keeping id: UUID) {
        let onScreen = Set(windows.flatMap(\.visibleTabIDs))
        // Never unloaded: pages on another engine (call tabs, on Chromium), which would end a call,
        // and busy pages (a call, playing audio, a half-written message).
        let evictable = { (t: UUID) in
            t != id && !onScreen.contains(t)
                && self.controllers[t]?.page.state.isLoading != true
                && self.controllers[t]?.page.state.isBusy != true
                && self.controllers[t]?.engineID ?? self.engine.info.id == self.engine.info.id
        }
        while lru.count > capacity, let victim = lru.first(where: evictable) {
            unload(victim)
        }
    }

    /// Saves a page's back/forward list onto its tab and lets the page go.
    private func unload(_ id: UUID) {
        unload(id, then: {})
    }

    private func unloadAndWait(_ id: UUID) async {
        await withCheckedContinuation { continuation in
            unload(id) { continuation.resume() }
        }
    }

#if DEBUG
    func unloadForDebugCheck(_ id: UUID) async { await unloadAndWait(id) }
#endif

    private func unload(_ id: UUID, then completion: @escaping @MainActor () -> Void) {
        if unloadCompletions[id] != nil {
            unloadCompletions[id, default: []].append(completion)
            return
        }
        unloadCompletions[id] = [completion]
        videoPictureInPicture.beforeTabUnload(id) { [weak self] in
            guard let self else { completion(); return }
            self.videoMiniPlayer.beforeTabUnload(id) { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self else { completion(); return }
                    await self.finishUnload(id)
                    let completions = self.unloadCompletions.removeValue(forKey: id) ?? []
                    completions.forEach { $0() }
                }
            }
        }
    }

    private func finishUnload(_ id: UUID) async {
        if let c = controllers[id] {
            let scrollState = await c.captureInnerScroll()
            c.freeze()
            if space(containing: c.tab) != nil, let scrollState {
                let openIDs = Set(allTabs.map(\.id))
                sleepingScrollStates = sleepingScrollStates.filter { openIDs.contains($0.key) }
                if sleepingScrollStates[id] == nil, sleepingScrollStates.count >= 64,
                   let oldest = sleepingScrollStates.keys.first {
                    sleepingScrollStates[oldest] = nil
                }
                sleepingScrollStates[id] = scrollState
            } else {
                sleepingScrollStates[id] = nil
            }
            c.page.close()
            c.tab.call = nil
        }
        controllers[id] = nil
        lru.removeAll { $0 == id }
    }

    // MARK: Opening tabs

    /// A new today tab at the top of a space. Opening into Private makes the Private space.
    @discardableResult
    func insertTab(url: URL?, in space: Space, isPrivate: Bool = false, source: Frecency.VisitSource = .typed,
                   at index: Int = 0, for window: Browser? = nil, promoting glance: GlanceSession? = nil) -> BrowserTab {
        let wantsPrivate = isPrivate || space.isPrivate
        let target = wantsPrivate ? openPrivateSpace() : space
        // vx-bot/NOTE: Extension pages need their context's configuration when the web view is created.
        let extensionURL = url?.scheme == "webkit-extension" ? url : nil
        let tab = BrowserTab(url: extensionURL, isPrivate: wantsPrivate)
        tab.windowKey = (window ?? activeWindow)?.windowKey
        target.today.insert(tab, at: min(index, target.today.count))
        if let url, let glance, glance.loadedURL == url, !glance.page.state.isLoading,
           glance.profile == browsingProfile(for: tab), engine(for: tab, url: url).info.id == engine.info.id,
           cleanedNavigationURL(url) == nil {
            let controller = TabController(tab: tab, library: self) { _ in glance.page }
            adopt(controller)
            controller.registerPromotedPage(url: url, source: source)
        } else {
            glance?.page.close()
            if let url {
                let controller = controller(for: tab)
                if extensionURL == nil { controller.load(url, source: source) }
            }
        }
        scheduleSave()
        return tab
    }

    /// Cmd-click on a link: a new today tab just under the one it came from.
    func openInNewTab(_ url: URL, from opener: BrowserTab, foreground: Bool) {
        let space = space(containing: opener) ?? regularSpaces[0]
        let after = space.today.firstIndex { $0.id == opener.id }.map { $0 + 1 } ?? 0
        let window = window(showing: opener)
        let tab = insertTab(url: url, in: space, isPrivate: opener.isPrivate, source: .link, at: after,
                            for: window ?? owner(of: opener))
        if foreground { window?.select(tab) } else { window?.showToast("Opened in background") }
    }

    /// A page opened a window. It becomes a tab right after its opener, in front.
    func openPopup(from opener: BrowserTab, page: any EnginePage, url: URL?) -> TabController {
        let space = space(containing: opener) ?? regularSpaces[0]
        let tab = BrowserTab(url: url, isPrivate: opener.isPrivate)
        let after = space.today.firstIndex { $0.id == opener.id }.map { $0 + 1 } ?? 0
        let window = window(showing: opener) ?? activeWindow
        tab.windowKey = window?.windowKey
        space.today.insert(tab, at: after)
        let c = TabController(tab: tab, library: self) { _ in page }
        adopt(c)
        window?.select(tab)
        scheduleSave()
        return c
    }

    // MARK: Closing

    func close(_ tab: BrowserTab) {
        if let closeGuard, !closeGuard(tab) { return }
        for w in windows { w.cancelPrompts(for: tab.id) }
        if !tab.isPrivate, !tab.isPinned, tab.url != nil {
            controllers[tab.id]?.freeze()
            recentlyClosed.append(tab)
            if recentlyClosed.count > 30 { recentlyClosed.removeFirst() }
        }
        guard let space = space(containing: tab) else { return }
        if tab.isPrivate {
            privateSiteShapes[tab.id] = nil
            let prefix = "\(tab.id.uuidString):"
            privateReloadWithoutCacheSites = privateReloadWithoutCacheSites.filter { !$0.hasPrefix(prefix) }
        }
        let index = space.today.firstIndex { $0.id == tab.id }
        let blankWindows = windows.filter { window in
            Preferences.newTabAfterLast && !Preferences.closeTabGoesBack && !tab.isPrivate && !tab.isPinned
                && window.currentTab === tab && window.today(in: space).count == 1 && !space.pinned.isEmpty
                && window.activeSplit?.contains(tab.id) != true
        }
        // Windows showing it move on first, while it's still in the list to measure from.
        for w in windows { w.moveOff(tab, in: space, closing: true) }
        space.today.removeAll { $0.id == tab.id }
        for window in blankWindows { window.newTab(url: nil, in: space) }
        sleepingScrollStates[tab.id] = nil
        if space.selectedTabID == tab.id { space.selectedTabID = nil }
        if index == nil, tab.isPinned {
            // Closing a pinned tab only unloads it, like Arc.
        }
        unload(tab.id)
        if let p = privateSpace, p.allTabs.isEmpty { closePrivateSpace() }
        scheduleSave()
    }

    func popRecentlyClosed() -> BrowserTab? { recentlyClosed.popLast() }

    // MARK: Organising

    func togglePinned(_ tab: BrowserTab) {
        guard !tab.isPrivate, let space = space(containing: tab) else { return }
        if tab.isPinned {
            space.pinned.removeAll { $0.id == tab.id }
            space.setPinFolder(nil, for: tab)
            space.today.insert(tab, at: 0)
            tab.windowKey = (window(showing: tab) ?? activeWindow)?.windowKey
            tab.pinnedHomeURL = nil
        } else {
            space.today.removeAll { $0.id == tab.id }
            space.pinned.append(tab)
            tab.pinnedHomeURL = tab.url
        }
        tab.isPinned.toggle()
        if let page = existingController(for: tab)?.page { engine.pagePinDidChange(page) }
        scheduleSave()
    }

    /// Drag and drop in the sidebar: `tab` lands just before `target`, or at the end of the section in `fallback`.
    func move(_ tab: BrowserTab, before target: BrowserTab?, pinned: Bool, fallback: Space, folderID: UUID? = nil) {
        guard let from = space(containing: tab), !(tab.isPrivate && pinned) else { return }
        let to = target.flatMap(space(containing:)) ?? fallback
        if pinned, from.id == to.id,
           let members = from.splitGroup(in: from.allTabs), members.contains(where: { $0.id == tab.id }),
           members.count > 1 {
            guard target.map({ target in !members.contains(where: { $0.id == target.id }) }) ?? true else { return }
            let ordered = members
            if let target {
                for member in ordered.reversed() {
                    moveSingle(member, before: target, pinned: true, fallback: fallback, folderID: folderID)
                }
            } else {
                for member in ordered {
                    moveSingle(member, before: nil, pinned: true, fallback: fallback, folderID: folderID)
                }
            }
            return
        }
        moveSingle(tab, before: target, pinned: pinned, fallback: fallback, folderID: folderID)
    }

    private func moveSingle(_ tab: BrowserTab, before target: BrowserTab?, pinned: Bool, fallback: Space, folderID: UUID?) {
        guard let from = space(containing: tab), !(tab.isPrivate && pinned) else { return }
        let to = target.flatMap(space(containing:)) ?? fallback
        guard from.isPrivate == to.isPrivate else { return }
        if let folderID {
            guard pinned, !to.isPrivate, to.pinFolders.contains(where: { $0.id == folderID }) else { return }
        }
        let showingPinnedWindow = tab.isPinned && from.id == to.id ? window(showing: tab) : nil
        if browsingProfile(in: from) != browsingProfile(in: to) {
            resetBrowsingSession(of: tab)
            pageSwaps += 1
        }
        from.pinned.removeAll { $0.id == tab.id }
        from.setPinFolder(nil, for: tab)
        from.today.removeAll { $0.id == tab.id }
        if pinned && !tab.isPinned { tab.pinnedHomeURL = tab.url }
        if !pinned { tab.pinnedHomeURL = nil }
        let pinChanged = tab.isPinned != pinned
        tab.isPinned = pinned
        if pinned {
            let i = target.flatMap { t in to.pinned.firstIndex { $0.id == t.id } } ?? to.pinned.endIndex
            to.pinned.insert(tab, at: i)
            to.setPinFolder(folderID, for: tab)
        } else {
            let i = target.flatMap { t in to.today.firstIndex { $0.id == t.id } } ?? to.today.endIndex
            to.today.insert(tab, at: i)
            // Dropped in Today: it joins the window it was dropped in.
            tab.windowKey = showingPinnedWindow?.windowKey ?? activeWindow?.windowKey ?? target?.windowKey
        }
        if from.id != to.id { for w in windows { w.tabLeft(tab, space: from) } }
        if pinChanged, let page = existingController(for: tab)?.page { engine.pagePinDidChange(page) }
        scheduleSave()
    }

    func move(_ tab: BrowserTab, to space: Space) {
        guard let from = self.space(containing: tab), from.id != space.id, !space.isPrivate, !tab.isPrivate else { return }
        for w in windows { w.moveOff(tab, in: from) }
        if browsingProfile(in: from) != browsingProfile(in: space) {
            resetBrowsingSession(of: tab)
            pageSwaps += 1
        }
        from.pinned.removeAll { $0.id == tab.id }
        from.setPinFolder(nil, for: tab)
        from.today.removeAll { $0.id == tab.id }
        if from.selectedTabID == tab.id { from.selectedTabID = nil }
        if tab.isPinned { tab.windowKey = activeWindow?.windowKey }
        let wasPinned = tab.isPinned
        tab.isPinned = false
        tab.pinnedHomeURL = nil
        space.today.insert(tab, at: 0)
        if wasPinned, let page = existingController(for: tab)?.page { engine.pagePinDidChange(page) }
        scheduleSave()
    }

    /// Site permission answers visible to a tab. Private answers override saved answers but stay in memory.
    func sitePermissions(for host: String, isPrivate: Bool) -> [String: Bool] {
        let saved = settings.sitePermissions[host] ?? [:]
        guard isPrivate else { return saved }
        return saved.merging(privatePermissions[host] ?? [:]) { _, privateAnswer in privateAnswer }
    }

    /// Private answers last until the private space closes and are never written to settings.
    func setSitePermission(_ key: String, _ value: Bool?, for host: String, isPrivate: Bool) {
        if isPrivate {
            var answers = privatePermissions[host] ?? [:]
            answers[key] = value
            privatePermissions[host] = answers.isEmpty ? nil : answers
        } else {
            var answers = settings.sitePermissions[host] ?? [:]
            answers[key] = value
            settings.sitePermissions[host] = answers.isEmpty ? nil : answers
        }
    }

    // MARK: Favourites

    func favorites(for profileID: UUID?) -> [Favorite] {
        favoritesByProfile[FavoriteProfileKey.key(for: profileID)] ?? []
    }

    func isFavorite(_ url: URL, profileID: UUID? = nil) -> Bool {
        let key = URLNormalizer.key(for: url)
        return favorites(for: profileID).contains { URLNormalizer.key(for: $0.url) == key }
    }

    func addFavorite(url: URL, title: String, profileID: UUID? = nil) {
        let key = FavoriteProfileKey.key(for: profileID)
        var items = favorites(for: profileID)
        guard !isFavorite(url, profileID: profileID) else { return }
        items.append(Favorite(url: url, title: title, order: (items.map(\.order).max() ?? -1) + 1))
        favoritesByProfile[key] = items
        Task { await profileHistory.store(for: profileID).setBookmarked(url, true) }
        scheduleSave()
    }

    func removeFavorite(_ fav: Favorite, profileID: UUID? = nil) {
        let key = FavoriteProfileKey.key(for: profileID)
        favoritesByProfile[key, default: []].removeAll { $0.id == fav.id }
        // Its tabs go back to being ordinary Today tabs.
        for tab in allTabs where tab.favoriteID == fav.id { tab.favoriteID = nil }
        Task { await profileHistory.store(for: profileID).setBookmarked(fav.url, false) }
        scheduleSave()
    }

    func moveFavorite(_ fav: Favorite, before target: Favorite?, profileID: UUID? = nil) {
        var sorted = sortedFavorites(for: profileID)
        sorted.removeAll { $0.id == fav.id }
        let i = target.flatMap { t in sorted.firstIndex { $0.id == t.id } } ?? sorted.endIndex
        sorted.insert(fav, at: i)
        for j in sorted.indices { sorted[j].order = j }
        favoritesByProfile[FavoriteProfileKey.key(for: profileID)] = sorted
        scheduleSave()
    }

    func sortedFavorites(for profileID: UUID?) -> [Favorite] { favorites(for: profileID).sorted { $0.order < $1.order } }

    // MARK: Spaces

    @discardableResult
    func addSpace() -> Space {
        let used = Set(spaces.map(\.colorIndex))
        let color = (0..<SpacePalette.colors.count).first { !used.contains($0) } ?? spaces.count
        let space = Space(name: "Space \(regularSpaces.count + 1)", symbol: "circle.fill", colorIndex: color)
        spaces.insert(space, at: spaces.firstIndex { $0.isPrivate } ?? spaces.endIndex)
        scheduleSave()
        return space
    }

    /// Moves a space to where another one is, for dragging spaces into order in Settings. The Private space
    /// stays last.
    func moveSpace(_ id: UUID, to target: UUID) {
        guard id != target, let from = spaces.firstIndex(where: { $0.id == id }), !spaces[from].isPrivate,
              let to = spaces.firstIndex(where: { $0.id == target }), !spaces[to].isPrivate else { return }
        let space = spaces.remove(at: from)
        spaces.insert(space, at: to)
        scheduleSave()
    }

    /// Reorders the regular spaces (as listed in Settings), leaving the Private space where it is.
    func moveSpaces(fromOffsets source: IndexSet, toOffset destination: Int) {
        var regular = regularSpaces
        regular.move(fromOffsets: source, toOffset: destination)
        var next = regular.makeIterator()
        spaces = spaces.map { $0.isPrivate ? $0 : next.next()! }
        scheduleSave()
    }

    func deleteSpace(_ space: Space) {
        if space.isPrivate { closePrivateSpace(); return }
        guard regularSpaces.count > 1, let i = spaces.firstIndex(where: { $0.id == space.id }) else { return }
        space.allTabs.forEach { unload($0.id) }
        spaces.remove(at: i)
        for window in windows { window.splitBySpace[space.id] = nil }
        for w in windows where w.selectedSpaceID == space.id { w.leaveSpace() }
        if settings.externalLinksSpaceID == space.id { settings.externalLinksSpaceID = nil }
        scheduleSave()
    }

    func openPrivateSpace() -> Space {
        if let privateSpace { return privateSpace }
        let space = Space(name: "Private", symbol: "eye.slash", colorIndex: 0, isPrivate: true)
        spaces.append(space)
        return space
    }

    /// Closes every private tab, which removes the Private space and throws its cookies away.
    func closePrivateSpace() {
        guard let space = privateSpace else { return }
        for tab in space.allTabs {
            for w in windows { w.cancelPrompts(for: tab.id) }
            unload(tab.id)
        }
        for w in windows where w.selectedSpaceID == space.id { w.leaveSpace() }
        spaces.removeAll { $0.id == space.id }
        privateReloadWithoutCacheSites.removeAll()
        privateSiteShapes.removeAll()
        privatePermissions = [:]
        privateCertificateExceptions = [:]
        engine.resetEphemeralProfile()
        scheduleSave()
    }

    // MARK: Archive

    /// Today tabs left alone for longer than the setting go to the archive, like Arc.
    func archiveStaleTabs(now: Date = .now) {
        let onScreen = Set(windows.flatMap(\.visibleTabIDs))
        for space in spaces where !space.isPrivate {
            let stale = space.today.filter {
                !onScreen.contains($0.id) && $0.id != space.selectedTabID
                    && now.timeIntervalSince($0.lastActive) > settings.archiveAfterHours * 3600
            }
            guard !stale.isEmpty else { continue }
            let staleIDs = Set(stale.map(\.id))
            for window in windows {
                if let split = window.splitBySpace[space.id], split.tabs.contains(where: staleIDs.contains) {
                    window.splitBySpace[space.id] = nil
                }
            }
            space.today.removeAll { staleIDs.contains($0.id) }
            for tab in stale {
                unload(tab.id)
                tab.websiteSessionProfileID = space.websiteProfileID
            }
            archive.insert(contentsOf: stale, at: 0)
        }
        archive = Array(archive.prefix(500))
        scheduleSave()
    }

    func takeFromArchive(_ tab: BrowserTab, into space: Space, for window: Browser? = nil) {
        archive.removeAll { $0.id == tab.id }
        tab.lastActive = .now
        tab.windowKey = (window ?? activeWindow)?.windowKey
        space.today.insert(tab, at: 0)
        scheduleSave()
    }

    func clearArchive() {
        archive.removeAll()
        scheduleSave()
    }

    // MARK: Blocking and privacy

    func applyBlocking() {
        let s = settings
        let config = BlockingConfiguration(isEnabled: s.blockContent, ruleGroups: Set(s.filterGroups.map(\.rawValue)),
                                           allowlist: s.blockingDisabledHosts, declineCookieBanners: s.declineCookieBanners,
                                           globalPrivacyControl: globalPrivacyControl)
        blockingTask?.cancel()
        blockingTask = Task { [weak self] in
            guard let self else { return }
            await engine.applyBlocking(config)
            refreshFilterStatus()
            if s.blockContent, !filterStatus.isUpdating { await updateFilters(force: false) }
        }
    }

    /// Waits for blocking settings being applied right now.
    func blockingApplied() async { await blockingTask?.value }

    func updateFilters(force: Bool) async {
        guard ContentBlocker.rulesBaseURL != nil, !filterStatus.isUpdating else { return }
        filterStatus.isUpdating = true
        filterStatus.error = nil
        do {
            _ = try await engine.updateBlockingRules(force: force)
        } catch {
            filterStatus.error = "Couldn't update filters. \(error.localizedDescription)"
        }
        filterStatus.isUpdating = false
        refreshFilterStatus()
    }

    private func refreshFilterStatus() {
        let meta = ContentBlocker.shared.metadata
        filterStatus.lastUpdated = meta.lastUpdated
        filterStatus.ruleCount = settings.filterGroups.reduce(0) { $0 + (meta.ruleCounts[$1.rawValue] ?? 0) }
    }

    func clearWebsiteData() async {
        await engine.clearWebsiteData(for: .standard)
        for id in Set(settings.websiteProfiles.map(\.id) + regularSpaces.compactMap(\.websiteProfileID)) {
            await engine.clearWebsiteData(for: .named(id))
        }
        for w in windows where w.currentTab?.isPrivate == false { w.currentController?.page.reload() }
    }

    func clearHistory() async {
        await profileHistory.clearAll(profileIDs: Set(settings.websiteProfiles.map(\.id) + regularSpaces.compactMap(\.websiteProfileID)))
        archive.removeAll()
        recentlyClosed.removeAll()
        scheduleSave()
    }

    func forgetPermissions(for host: String) {
        settings.sitePermissions[host] = nil
    }

    // MARK: Suggestions

    func makeSuggestEngine(for window: Browser) -> SuggestEngine {
        let profileID = window.currentSpace.websiteProfileID
        let inPrivate = window.currentSpace.isPrivate
        return SuggestEngine(
            history: profileHistory.store(for: profileID),
            favorites: { [weak self] in await MainActor.run { self?.favorites(for: profileID) ?? [] } },
            openTabs: { [weak self, weak window] in
                await MainActor.run {
                    guard let self, let window else { return [] }
                    return self.spaces.filter { $0.websiteProfileID == profileID && (inPrivate || !$0.isPrivate) }
                        .flatMap(\.allTabs)
                        .filter { $0.url != nil && $0.id != window.currentTab?.id }
                        .sorted { $0.lastActive > $1.lastActive }
                        .map { OpenTabSnapshot(id: $0.id, url: $0.url!, title: $0.title) }
                }
            },
            seeds: suggestionSeeds,
            searchEngine: settings.searchEngine,
            remoteSuggestionsEnabled: settings.remoteSuggestions,
            extraProviders: [
                CommandProvider(commands: { [weak window] in
                    await MainActor.run { window?.availableCommands() ?? [] }
                }),
                ArchivedTabsProvider(tabs: { [weak self] in
                    await MainActor.run {
                        (self?.archive ?? []).filter { $0.websiteSessionProfileID == profileID }
                            .compactMap { t in t.url.map { OpenTabSnapshot(id: t.id, url: $0, title: t.title) } }
                    }
                }),
            ])
    }

    // MARK: Persistence

    func scheduleSave() {
        guard snapshotURL != nil else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow(sync: Bool = true) {
        guard let snapshotURL else { return }
        for c in controllers.values { c.freeze() }
        // Next launch opens on the space the active window shows (never Private).
        let shown = activeWindow?.currentSpace
        let selected = shown.flatMap { $0.isPrivate ? nil : $0.id } ?? launchSpaceID
        launchSpaceID = selected
        let snap = BrowserSnapshot(spaces: regularSpaces.map(\.record), selectedSpaceID: selected,
                                   favorites: favorites(for: nil), archive: archive.map(\.record), settings: settings,
                                   saved: savedSites, profileFavorites: favoritesByProfile)
        guard let data = try? JSONEncoder().encode(snap) else { return }
        try? FileManager.default.createDirectory(at: snapshotURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: snapshotURL, options: .atomic)
        Task { await profileHistory.saveNow() }
        if sync, syncCoordinator.isConfigured {
            Task { [weak self] in await self?.syncNow() }
        }
    }

    func syncNow() async {
        let local = currentSnapshot()
        guard let merged = await syncCoordinator.synchronize(local),
              BrowserSyncItems.values(from: local) != BrowserSyncItems.values(from: merged) else { return }
        applySyncedSnapshot(merged)
    }

    private func currentSnapshot() -> BrowserSnapshot {
        let shown = activeWindow?.currentSpace
        let selected = shown.flatMap { $0.isPrivate ? nil : $0.id } ?? launchSpaceID
        return BrowserSnapshot(spaces: regularSpaces.map(\.record), selectedSpaceID: selected,
                               favorites: favorites(for: nil), archive: archive.map(\.record), settings: settings,
                               saved: savedSites, profileFavorites: favoritesByProfile)
    }

    private func applySyncedSnapshot(_ snapshot: BrowserSnapshot) {
        isApplyingSync = true
        defer { isApplyingSync = false }

        let oldRegularSpaces = regularSpaces
        let existingSpaces = Dictionary(uniqueKeysWithValues: oldRegularSpaces.map { ($0.id, $0) })
        let existingTabs = Dictionary(uniqueKeysWithValues: regularSpaces.flatMap(\.allTabs).map { ($0.id, $0) })
        let oldTabProfiles = Dictionary(uniqueKeysWithValues: oldRegularSpaces.flatMap { space in
            space.allTabs.map { ($0.id, space.websiteProfileID) }
        })
        var retainedTabIDs: Set<UUID> = []

        func tab(_ record: TabRecord, profileID: UUID?) -> BrowserTab {
            retainedTabIDs.insert(record.id)
            let result = existingTabs[record.id] ?? BrowserTab(record)
            let profileChanged = existingTabs[record.id] != nil && oldTabProfiles[record.id, default: nil] != profileID
            if existingTabs[record.id] != nil, result.url != record.url || profileChanged {
                resetBrowsingSession(of: result)
            }
            result.url = record.url
            result.title = record.title
            result.isPinned = record.isPinned
            result.pinnedHomeURL = record.resolvedPinnedHomeURL
            result.lastActive = record.lastActive
            result.interactionState = profileChanged ? nil : record.interactionState
            result.isPrivate = false
            result.favoriteID = record.favoriteID
            result.windowKey = record.windowKey
            result.customTitle = record.customTitle
            result.websiteSessionProfileID = profileChanged ? nil : record.websiteSessionProfileID
            return result
        }

        let restored = snapshot.spaces.map { record -> Space in
            let space = existingSpaces[record.id] ?? Space(record)
            if existingSpaces[record.id] != nil, space.websiteProfileID != record.websiteProfileID {
                for window in windows where window.selectedSpaceID == space.id {
                    window.closeGlance()
                    window.reader = nil
                    window.commandBar = nil
                }
            }
            space.name = record.name
            space.symbol = record.symbol
            space.colorIndex = record.colorIndex
            space.themeHue = record.themeHue
            space.themeShade = record.themeShade
            space.appearance = record.appearance
            space.pinned = record.pinned.map { tab($0, profileID: record.websiteProfileID) }
            for (pinRecord, pin) in zip(record.pinned, space.pinned) {
                space.setPinFolder(pinRecord.pinFolderID, for: pin)
            }
            space.today = record.today.map { tab($0, profileID: record.websiteProfileID) }
            space.selectedTabID = record.selectedTabID
            space.isSidebarOpen = record.isSidebarOpen
            space.websiteProfileID = record.websiteProfileID
            space.isSyncLocalOnly = record.isSyncLocalOnly
            space.restorePinFolders(record.pinFolders ?? [])
            return space
        }

        let remoteIDs = Set(restored.map(\.id))
        for space in oldRegularSpaces where !remoteIDs.contains(space.id) {
            for tab in space.allTabs where !retainedTabIDs.contains(tab.id) { unload(tab.id) }
        }
        for tab in existingTabs.values where !retainedTabIDs.contains(tab.id) { unload(tab.id) }

        spaces = restored + spaces.filter(\.isPrivate)
        pageSwaps += 1
        for window in windows where !remoteIDs.contains(window.selectedSpaceID) { window.leaveSpace() }
        launchSpaceID = snapshot.selectedSpaceID.flatMap { id in restored.first { $0.id == id }?.id }
            ?? restored.first?.id ?? launchSpaceID
        favoritesByProfile = snapshot.profileFavorites ?? [FavoriteProfileKey.default: snapshot.favorites]
        if let settings = snapshot.settings { self.settings = settings }
        saveNow(sync: false)
    }
}

// MARK: - Extensions

/// Windows and tabs as extensions see them: each window's current space, its live tabs in order.
extension Library: EngineExtensionHost {
    var extensionWindows: [EngineWindowInfo] {
        let focused = activeWindow
        let ordered = focused.map { f in [f] + windows.filter { $0 !== f } } ?? windows
        return ordered.map { w in
            let space = w.currentSpace
            return EngineWindowInfo(id: w.id,
                                    pages: space.allTabs.filter(w.lists).compactMap { existingController(for: $0)?.page },
                                    activePage: w.currentTab.flatMap { existingController(for: $0)?.page },
                                    isFocused: w === focused, isPrivate: space.isPrivate,
                                    frame: w.nsWindow?.frame ?? .zero)
        }
    }

    /// chrome.sidePanel.open, or a toolbar click on an extension that asked for its panel instead.
    func showExtensionPanel(extensionID: String, pageURL: URL? = nil) -> Bool {
        let id = "ext:" + extensionID
        guard workbench.tool(id) != nil, let window = activeWindow else { return false }
        if let pageURL { workbench.setExtensionPanelPage(pageURL, for: extensionID) }
        window.showPanel(id)
        return true
    }

    func openExtensionPanels(extensionID: String) -> [URL] {
        shownExtensionPanels[extensionID].map { [$0] } ?? []
    }

    func focusExtensionWindow(_ id: UUID) {
        windows.first { $0.id == id }?.nsWindow?.makeKeyAndOrderFront(nil)
    }

    func openExtensionTab(url: URL?, windowID: UUID?, active: Bool) -> (any EnginePage)? {
        openExtensionTab(url: url, windowID: windowID, active: active, pinned: false)
    }

    func openExtensionTab(url: URL?, windowID: UUID?, active: Bool, pinned: Bool) -> (any EnginePage)? {
        guard let window = windows.first(where: { $0.id == windowID }) ?? activeWindow else { return nil }
        guard !pinned || !window.currentSpace.isPrivate else { return nil }
        // The page is made with its URL, so an extension page gets the web view setup it needs.
        let tab = BrowserTab(url: url, isPrivate: window.currentSpace.isPrivate)
        tab.windowKey = window.windowKey
        window.currentSpace.today.insert(tab, at: 0)
        if pinned { togglePinned(tab) }
        let page = controller(for: tab).page
        if active {
            window.select(tab)
            // WebKit needs a real tab object to return to the extension. Let the user fill that
            // blank tab through Ark's command bar instead of creating a second tab on submit.
            if url == nil && !pinned { window.showCommandBar(.editCurrent) }
        }
        scheduleSave()
        return page
    }

    func isExtensionTabPinned(_ page: any EnginePage) -> Bool { tab(showing: page)?.isPinned ?? false }

    func setExtensionTabPinned(_ page: any EnginePage, pinned: Bool) -> Bool {
        guard let tab = tab(showing: page), space(containing: tab) != nil else { return false }
        if tab.isPinned == pinned { return true }
        guard !tab.isPrivate else { return false }
        togglePinned(tab)
        return tab.isPinned == pinned
    }

    func activateExtensionTab(_ page: any EnginePage) {
        guard let tab = tab(showing: page) else { return }
        (window(showing: tab) ?? activeWindow)?.select(tab)
    }

    func closeExtensionTab(_ page: any EnginePage) {
        guard let tab = tab(showing: page) else { return }
        (window(showing: tab) ?? activeWindow)?.close(tab)
    }

    private func tab(showing page: any EnginePage) -> BrowserTab? {
        controllers.values.first { $0.page === page }?.tab
    }
}
