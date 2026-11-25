#if os(macOS)
import AppKit
import WebKit
import CryptoKit
import BrowserEngine
import BrowserCore

/// Web extensions run by WebKit's WKWebExtensionController: Safari extensions inside the user's
/// apps, and unpacked folders (store installs and ones the user picked).
///
/// Extensions get the permissions they ask for: the user saw them on the add sheet, or, for
/// Safari extensions, when they installed the app. Per-site prompts come later.
@available(macOS 15.4, *)
@MainActor
final class WebKitExtensions: NSObject, WKWebExtensionControllerDelegate {
    let controller: WKWebExtensionController = {
        // An extension's background has no window, so WebKit treats its process as inactive and can
        // pause it mid-task. Extension web views are never paused (see also startKeepAlive).
        let configuration = WKWebExtensionController.Configuration.default()
        configuration.webViewConfiguration?.preferences.inactiveSchedulingPolicy = .none
        // Keep extension backgrounds on the same Safari engine version as Ark's tabs.
        configuration.webViewConfiguration?.applicationNameForUserAgent = SafariUserAgent.applicationName
        return WKWebExtensionController(configuration: configuration)
    }()
    weak var host: (any EngineExtensionHost)?
    private(set) var loaded: [EngineExtension] = []
    private var contexts: [String: WKWebExtensionContext] = [:]
    private var loadGeneration = UUID()
    private var windows: [UUID: ExtensionWindow] = [:]
    private var popupNavigationDelegates: [ObjectIdentifier: ExtensionActionPopupNavigationDelegate] = [:]
    /// Where the popup of the button being clicked should appear.
    private weak var popupAnchor: NSView?

    static let extensionPoint = "com.apple.Safari.web-extension"

    override init() {
        super.init()
        controller.delegate = self
    }

    // MARK: Finding and loading

    /// Safari web extension bundles inside the apps in /Applications and ~/Applications.
    static func installedBundles() -> (found: [URL], problems: [String]) {
        let fm = FileManager.default
        var found: [URL] = [], problems: [String] = []
        let roots = [URL(fileURLWithPath: "/Applications"),
                     fm.homeDirectoryForCurrentUser.appending(path: "Applications")]
        for root in roots {
            let apps: [URL]
            do {
                apps = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).filter { $0.pathExtension == "app" }
            } catch {
                if root.path() != roots[1].path() { problems.append("can't list \(root.path()): \(error.localizedDescription)") }
                continue
            }
            for app in apps {
                let plugins = app.appending(path: "Contents/PlugIns")
                for appex in (try? fm.contentsOfDirectory(at: plugins, includingPropertiesForKeys: nil)) ?? []
                where appex.pathExtension == "appex" {
                    let info = Bundle(url: appex)?.infoDictionary?["NSExtension"] as? [String: Any]
                    if info?["NSExtensionPointIdentifier"] as? String == extensionPoint { found.append(appex) }
                }
            }
        }
        return (found, problems)
    }

    func loadInstalled(folders: [ExtensionFolder] = [], includeApps: Bool = true) async -> [String] {
        let generation = loadGeneration
        var (bundles, problems) = includeApps ? Self.installedBundles() : ([], [])
        // Unpacked extensions: Ark's store installs and folders the user picked.
        for folder in folders {
            let id = folder.id
            guard contexts[id] == nil else { continue }
            do {
                // Chrome extensions run from a copy with Ark's compat script in front of the background.
                let url = try ExtensionCompat.prepare(folder.url, id: id,
                                                      in: AppFolders.support.appending(path: "Extensions (WebKit)"))
                let ext = try await WKWebExtension(resourceBaseURL: url)
                guard generation == loadGeneration else { return problems }
                let context = WKWebExtensionContext(for: ext)
                context.uniqueIdentifier = id
                // The same address every launch, so restored tabs showing the extension's pages still work.
                context.baseURL = Self.stableBaseURL(for: id)
                context.isInspectable = true
                context.hasAccessToPrivateData = WebKitExtensionsPrivacy.isAllowed(id)
                grantRequestedPermissions(context)
                try controller.load(context)
                contexts[id] = context
                startKeepAlive(context, folder: url)
                loaded.append(describe(ext, context: context, id: id))
                problems += (ext.errors + context.errors).map { "\(id): \($0.localizedDescription)" }
            } catch {
                guard generation == loadGeneration else { return problems }
                problems.append("\(id): \(error)")
            }
        }
        // A Safari-app extension is skipped when the same extension came from a store or folder: the
        // Safari copy expects to reach its desktop app, which Ark can't connect it to.
        let unpackedNames = Set(loaded.map { Self.comparableName($0.name) })
        for url in bundles {
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier, contexts[id] == nil else { continue }
            do {
                let ext = try await WKWebExtension(appExtensionBundle: bundle)
                guard generation == loadGeneration else { return problems }
                if unpackedNames.contains(Self.comparableName(ext.displayName ?? "")) {
                    engineLog.info("extension: skipped the Safari copy of \(ext.displayName ?? id, privacy: .public); the store version is in use")
                    continue
                }
                let context = WKWebExtensionContext(for: ext)
                context.uniqueIdentifier = id
                // Without a fixed address WebKit picks a new one each launch, sees the change and
                // deletes the extension's local storage and IndexedDB, so its settings and sign-ins go.
                context.baseURL = Self.stableBaseURL(for: id)
                context.isInspectable = true
                context.hasAccessToPrivateData = WebKitExtensionsPrivacy.isAllowed(id)
                grantRequestedPermissions(context)
                try controller.load(context)
                contexts[id] = context
                loaded.append(describe(ext, context: context, id: id))
                problems += (ext.errors + context.errors).map { "\(id): \($0.localizedDescription)" }
                engineLog.info("extension loaded: \(id, privacy: .public)")
            } catch {
                guard generation == loadGeneration else { return problems }
                problems.append("\(id): \(error.localizedDescription)")
            }
        }
        for p in problems { engineLog.error("extension: \(p, privacy: .public)") }
        // Tabs that were open before the extensions arrived.
        if let any = contexts.values.first {
            for window in currentWindows() {
                controller.didOpenWindow(window)
                window.tabs(for: any).forEach(controller.didOpenTab)
            }
        }
        if let focused = currentWindows().first { controller.didFocusWindow(focused) }
        return problems
    }

    /// The toolbar and Settings entry for a loaded extension, with its side panel page if it has one.
    /// "1Password – Password Manager" and "1Password" compare equal: the name up to any dash or colon.
    static func comparableName(_ name: String) -> String {
        let head = name.split(whereSeparator: { "–—-:|".contains($0) }).first.map(String.init) ?? name
        return head.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// Resolve manifest pages as URLs so query strings and fragments stay out of the filename.
    static func extensionPage(_ path: String, relativeTo baseURL: URL) -> URL? {
        let relativePath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return URL(string: relativePath, relativeTo: baseURL)?.absoluteURL
    }

    func applyPrivateAccess(_ id: String) {
        contexts[id]?.hasAccessToPrivateData = WebKitExtensionsPrivacy.isAllowed(id)
    }

    private func describe(_ ext: WKWebExtension, context: WKWebExtensionContext, id: String) -> EngineExtension {
        let icon = ext.icon(for: CGSize(width: 32, height: 32))?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        let manifest = ext.manifest
        let panelPath = ((manifest["side_panel"] as? [String: Any])?["default_path"] as? String)
            ?? ((manifest["sidebar_action"] as? [String: Any])?["default_panel"] as? String)
        // Some extensions use a disabled placeholder page to opt out of their side panel.
        let activePanelPath = panelPath.flatMap { $0.localizedCaseInsensitiveContains("disabled") ? nil : $0 }
        let panelURL = activePanelPath.flatMap { Self.extensionPage($0, relativeTo: context.baseURL) }
        return EngineExtension(id: id, name: ext.displayName ?? id, version: ext.version ?? "",
                               icon: icon, hasAction: context.action(for: nil) != nil, panelURL: panelURL,
                               optionsURL: context.optionsPageURL)
    }

    #if DEBUG
    /// Debug checks: each loaded extension's popup page, and its manifest.
    func debugPopups() -> [(id: String, name: String, popup: URL?, manifest: [String: Any], errors: [String])] {
        contexts.map { id, context in
            let m = context.webExtension.manifest
            let action = (m["action"] as? [String: Any]) ?? (m["browser_action"] as? [String: Any])
            let popup = (action?["default_popup"] as? String).flatMap { Self.extensionPage($0, relativeTo: context.baseURL) }
            let errors = (context.webExtension.errors + context.errors).map { "\($0.localizedDescription) \((($0 as NSError).userInfo[NSDebugDescriptionErrorKey] as? String) ?? "")" }
            return (id, context.webExtension.displayName ?? id, popup, m, errors)
        }
    }
    #endif

    /// Hidden pages keeping backgrounds awake, by extension id.
    private var keepAlives: [String: WKWebView] = [:]
    private var keepAliveTimers: [String: Timer] = [:]
    private var keepAliveLastPing: [String: Date] = [:]

    /// WebKit runs all of an extension's web content in one process and pauses that process once none of
    /// its pages are in use. A service worker isn't a web view, so `inactiveSchedulingPolicy` doesn't
    /// cover it: 1Password's background froze for minutes after sign-in with the popup closed. A hidden
    /// extension page that's never paused keeps the process running. It also pings the background every
    /// 20 s, since WebKit unloads a background that gets no events for 30 s (dropping its sync socket).
    private func startKeepAlive(_ context: WKWebExtensionContext, folder: URL) {
        let id = context.uniqueIdentifier
        guard FileManager.default.fileExists(atPath: folder.appending(path: ExtensionCompat.keepAlivePage).path(percentEncoded: false)),
              let configuration = context.webViewConfiguration else { return }
        configuration.preferences.inactiveSchedulingPolicy = .none
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.load(URLRequest(url: context.baseURL.appending(path: ExtensionCompat.keepAlivePage)))
        keepAlives[id] = web
        keepAliveLastPing[id] = Date()
        keepAliveTimers[id]?.invalidate()
        keepAliveTimers[id] = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self, weak web] _ in
            MainActor.assumeIsolated {
                guard let self, let web else { return }
                // A slow answer means the extension's process was paused.
                let sent = Date()
                let gap = sent.timeIntervalSince(self.keepAliveLastPing[id] ?? sent)
                self.keepAliveLastPing[id] = sent
                web.evaluateJavaScript("typeof ping === 'function' ? ping() : 0") { _, error in
                    let took = Date().timeIntervalSince(sent)
                    #if DEBUG
                    if took > 2 || gap > 30 || error != nil {
                        print("[ext] keep-alive \(id): answered after \(String(format: "%.1f", took)) s, \(String(format: "%.0f", gap)) s since last\(error.map { ", error \($0.localizedDescription)" } ?? "")")
                    }
                    #endif
                }
            }
        }
        #if DEBUG
        print("[ext] keep-alive page started for \(id)")
        #endif
    }

    /// webkit-extension://<uuid>/ derived from the extension's id.
    static func stableBaseURL(for id: String) -> URL {
        var bytes = Array(SHA256.hash(data: Data(id.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        let uuid = NSUUID(uuidBytes: bytes) as UUID
        return URL(string: "webkit-extension://\(uuid.uuidString.lowercased())/")!
    }

    private func grantRequestedPermissions(_ context: WKWebExtensionContext) {
        let ext = context.webExtension
        for p in ext.requestedPermissions.union(ext.optionalPermissions) {
            context.setPermissionStatus(.grantedExplicitly, for: p)
        }
        let patterns = ext.allRequestedMatchPatterns
        for pattern in patterns {
            // WebKit injects content scripts once for every granted match pattern. A broad
            // pattern already covers narrower paths on the same scheme (for example, a site's
            // /* covers /embed/*), so granting both can run the same script several times.
            let covered = patterns.contains { other in
                other.string != pattern.string
                    && other.scheme == pattern.scheme
                    && other.matches(pattern)
                    && (!pattern.matches(other) || other.string < pattern.string)
            }
            guard !covered else { continue }
            context.setPermissionStatus(.grantedExplicitly, for: pattern)
        }
        // Keep broad host access opt-in at the manifest level; otherwise an extension that lists a
        // few sites would still receive access to every page through WebKit's all-URLs grant.
        if ext.allRequestedMatchPatterns.contains(where: { $0.matchesAllURLs || $0.matchesAllHosts }) {
            context.setPermissionStatus(.grantedExplicitly, for: WKWebExtension.MatchPattern.allURLs())
        }
    }

    func unloadAll() {
        loadGeneration = UUID()
        keepAliveTimers.values.forEach { $0.invalidate() }
        keepAliveTimers.removeAll()
        keepAlives.values.forEach { $0.stopLoading() }
        keepAlives.removeAll()
        keepAliveLastPing.removeAll()
        for c in contexts.values { ExtensionOffscreen.close(for: c); try? controller.unload(c) }
        contexts = [:]
        popupNavigationDelegates.removeAll()
        loaded = []
    }

    // MARK: Actions

    func actionState(extensionID: String, for page: WebKitPage?) -> EngineActionState? {
        guard let context = contexts[extensionID], let action = context.action(for: page) else { return nil }
        let icon = action.icon(for: CGSize(width: 16, height: 16))?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        return EngineActionState(label: action.label, badgeText: action.badgeText, hasUnreadBadge: action.hasUnreadBadgeText,
                                 isEnabled: action.isEnabled, icon: icon)
    }

    func performAction(extensionID: String, for page: WebKitPage?, anchor: NSView?) {
        guard let context = contexts[extensionID] else { return }
        // The button opens the side panel when the extension asked for that
        // (chrome.sidePanel.setPanelBehavior({ openPanelOnActionClick: true })), or when it has a side
        // panel and no popup: in Chrome those extensions open their panel from the button, but some do it
        // from script WebKit doesn't run the same way (ChatGPT), so the button did nothing.
        let manifest = context.webExtension.manifest
        let hasPanel = (manifest["side_panel"] as? [String: Any])?["default_path"] != nil
            || (manifest["sidebar_action"] as? [String: Any])?["default_panel"] != nil
        let hasPopup = context.action(for: page)?.presentsPopup ?? false
        if ExtensionBridges.opensPanelOnAction(extensionID) || (hasPanel && !hasPopup),
           ExtensionBridges.panelOptions[extensionID]?.enabled != false,
           host?.showExtensionPanel(extensionID: extensionID, pageURL: ExtensionBridges.panelOptions[extensionID]?.path) == true { return }
        popupAnchor = anchor
        context.performAction(for: page)
    }

    /// Extension pages (popups aside) only load in web views made from their extension's configuration.
    func configuration(for url: URL) -> WKWebViewConfiguration? {
        guard url.scheme == "webkit-extension" else { return nil }
        return contexts.values.first { $0.baseURL.host() == url.host() }?.webViewConfiguration
    }

    // MARK: Tabs and windows

    func window(_ id: UUID) -> ExtensionWindow {
        if let w = windows[id] { return w }
        let w = ExtensionWindow(id: id, extensions: self)
        windows[id] = w
        return w
    }

    func currentWindows() -> [ExtensionWindow] {
        let infos = host?.extensionWindows ?? []
        windows = windows.filter { id, _ in infos.contains { $0.id == id } }
        return infos.map { window($0.id) }
    }

    func info(for id: UUID) -> EngineWindowInfo? { host?.extensionWindows.first { $0.id == id } }

    func windowInfo(containing page: WebKitPage) -> EngineWindowInfo? {
        host?.extensionWindows.first { $0.pages.contains { $0 === page } }
    }

    func pageOpened(_ page: WebKitPage) { if !contexts.isEmpty { controller.didOpenTab(page) } }
    func pageClosed(_ page: WebKitPage) { if !contexts.isEmpty { controller.didCloseTab(page, windowIsClosing: false) } }

    func pageActivated(_ page: WebKitPage) {
        guard !contexts.isEmpty else { return }
        if let info = windowInfo(containing: page) { controller.didFocusWindow(window(info.id)) }
        controller.didActivateTab(page, previousActiveTab: nil)
    }

    func pageChanged(_ page: WebKitPage) {
        guard !contexts.isEmpty else { return }
        controller.didChangeTabProperties([.URL, .title, .loading], for: page)
    }

    // MARK: WKWebExtensionControllerDelegate

    func webExtensionController(_ controller: WKWebExtensionController, openWindowsFor extensionContext: WKWebExtensionContext) -> [any WKWebExtensionWindow] {
        currentWindows()
    }

    func webExtensionController(_ controller: WKWebExtensionController, focusedWindowFor extensionContext: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        currentWindows().first
    }

    func webExtensionController(_ controller: WKWebExtensionController, openNewTabUsing configuration: WKWebExtension.TabConfiguration,
                                for extensionContext: WKWebExtensionContext,
                                completionHandler: @escaping ((any WKWebExtensionTab)?, (any Error)?) -> Void) {
        let windowID = (configuration.window as? ExtensionWindow)?.id
        let page = host?.openExtensionTab(url: configuration.url, windowID: windowID, active: configuration.shouldBeActive)
        completionHandler(page as? WebKitPage, nil)
    }

    /// Ark has no extension popup windows: a new window's tabs open as tabs in the window in use.
    func webExtensionController(_ controller: WKWebExtensionController, openNewWindowUsing configuration: WKWebExtension.WindowConfiguration,
                                for extensionContext: WKWebExtensionContext,
                                completionHandler: @escaping ((any WKWebExtensionWindow)?, (any Error)?) -> Void) {
        let windowID = host?.extensionWindows.first?.id
        for url in configuration.tabURLs {
            _ = host?.openExtensionTab(url: url, windowID: windowID, active: true)
        }
        completionHandler(currentWindows().first, nil)
    }

    func webExtensionController(_ controller: WKWebExtensionController, promptForPermissions permissions: Set<WKWebExtension.Permission>,
                                in tab: (any WKWebExtensionTab)?, for extensionContext: WKWebExtensionContext,
                                completionHandler: @escaping (Set<WKWebExtension.Permission>, Date?) -> Void) {
        completionHandler(permissions, nil)
    }

    func webExtensionController(_ controller: WKWebExtensionController, promptForPermissionToAccess urls: Set<URL>,
                                in tab: (any WKWebExtensionTab)?, for extensionContext: WKWebExtensionContext,
                                completionHandler: @escaping (Set<URL>, Date?) -> Void) {
        completionHandler(urls, nil)
    }

    func webExtensionController(_ controller: WKWebExtensionController, promptForPermissionMatchPatterns matchPatterns: Set<WKWebExtension.MatchPattern>,
                                in tab: (any WKWebExtensionTab)?, for extensionContext: WKWebExtensionContext,
                                completionHandler: @escaping (Set<WKWebExtension.MatchPattern>, Date?) -> Void) {
        completionHandler(matchPatterns, nil)
    }

    // Native messaging. WebKit only routes it to the handler inside an extension's own app, and
    // refuses it for extensions in a third-party browser, so there's nothing to forward to yet.
    // Ark plugins will message the app itself here (host "app.ark", see PluginRequest).

    func webExtensionController(_ controller: WKWebExtensionController, sendMessage message: Any, toApplicationWithIdentifier applicationIdentifier: String?,
                                for extensionContext: WKWebExtensionContext, replyHandler: @escaping (Any?, (any Error)?) -> Void) {
        #if DEBUG
        // The compat diagnostics (ARK_EXT_DIAGNOSTICS) log through native messaging to "ark.log".
        if applicationIdentifier == "ark.log" {
            print("[ext-log] \(Date().timeIntervalSince1970) \((message as? [String: Any])?["line"] ?? message)")
            replyHandler(nil, nil)
            return
        }
        #endif
        if applicationIdentifier == ExtensionOffscreen.applicationIdentifier {
            ExtensionOffscreen.handle(message, for: extensionContext, reply: replyHandler)
            return
        }
        if applicationIdentifier == ExtensionOffscreen.clipboardIdentifier {
            ExtensionOffscreen.writeClipboard(message, for: extensionContext, reply: replyHandler)
            return
        }
        if applicationIdentifier == ExtensionAuth.bridgeName {
            let permissions = extensionContext.webExtension.manifest["permissions"] as? [String] ?? []
            guard permissions.contains("identity") else {
                replyHandler(nil, NSError(domain: "Ark.ExtensionAuth", code: 2,
                                          userInfo: [NSLocalizedDescriptionKey: "This extension did not request identity permission."]))
                return
            }
            ExtensionAuth.handle(message as? [String: Any] ?? [:], extensionID: extensionContext.uniqueIdentifier,
                                 host: host, reply: replyHandler)
            return
        }
        if applicationIdentifier == "ark.management" {
            handleManagement(message as? [String: Any] ?? [:], from: extensionContext, reply: replyHandler)
            return
        }
        if let name = applicationIdentifier, ExtensionBridges.names.contains(name) {
            ExtensionBridges.handle(name, message: message, extensionID: extensionContext.uniqueIdentifier,
                                    displayName: extensionContext.webExtension.displayName ?? "An extension",
                                    baseURL: extensionContext.baseURL,
                                    host: host, reply: replyHandler)
            return
        }
        replyHandler(nil, Self.noNativeMessaging(applicationIdentifier))
    }

    /// chrome.management is implemented here so the caller's manifest permission is checked by
    /// native code, and disabled catalog installs remain visible without loading their contexts.
    private func handleManagement(_ request: [String: Any], from caller: WKWebExtensionContext,
                                  reply: @escaping (Any?, (any Error)?) -> Void) {
        let callerID = caller.uniqueIdentifier
        let action = request["action"] as? String ?? ""
        let askedID = request["id"] as? String ?? callerID
        let callerManifest = caller.webExtension.manifest
        // Optional permission declarations do not grant access by themselves. Ark currently wires
        // this bridge for required management permission only; a future optional-permission grant
        // flow must update the active-permission check before it can use this API.
        let hasManagementPermission = (callerManifest["permissions"] as? [String] ?? []).contains("management")

        switch action {
        case "getSelf":
            reply(managementInfo(for: callerID), nil)
        case "get":
            guard askedID == callerID || hasManagementPermission else {
                reply(nil, managementError("The extension never asked for ‘management’"))
                return
            }
            guard let info = managementInfo(for: askedID) else {
                reply(nil, managementError("Could not find extension with id \(askedID)."))
                return
            }
            reply(info, nil)
        case "getAll":
            guard hasManagementPermission else {
                reply(nil, managementError("The extension never asked for ‘management’"))
                return
            }
            reply(managementList(), nil)
        default:
            reply(nil, managementError("Unsupported chrome.management action"))
        }
    }

    private func managementList() -> [[String: Any]] {
        var entries: [String: [String: Any]] = [:]
        var order: [String] = []
        for item in host?.extensionManagementEntries ?? [] {
            order.append(item.id)
            entries[item.id] = managementInfo(item)
        }
        for item in loaded where entries[item.id] == nil { order.append(item.id) }
        for (id, context) in contexts { entries[id] = managementInfo(context, fallback: entries[id]) }
        return order.compactMap { entries[$0] }
    }

    private func managementInfo(for id: String) -> [String: Any]? {
        let fallback = host?.extensionManagementEntries.first { $0.id == id }.map { managementInfo($0) }
        if let context = contexts[id] { return managementInfo(context, fallback: fallback) }
        return fallback
    }

    private func managementInfo(_ entry: EngineExtensionManagementEntry) -> [String: Any] {
        var info: [String: Any] = [
            "id": entry.id, "name": entry.name, "shortName": entry.shortName, "version": entry.version,
            "description": entry.description, "enabled": entry.enabled, "type": "extension", "isApp": false,
            "installType": entry.installType, "mayDisable": true, "mayEnable": true,
            "offlineEnabled": entry.offlineEnabled, "permissions": entry.permissions,
            "hostPermissions": entry.hostPermissions,
        ]
        if let versionName = entry.versionName { info["versionName"] = versionName }
        if let homepage = entry.homepageURL { info["homepageUrl"] = homepage }
        if let options = entry.optionsURL { info["optionsUrl"] = options }
        if let icon = entry.iconDataURL { info["icons"] = [["size": 48, "url": icon]] }
        if !entry.enabled { info["disabledReason"] = "unknown" }
        return info
    }

    private func managementInfo(_ context: WKWebExtensionContext, fallback: [String: Any]? = nil) -> [String: Any] {
        let ext = context.webExtension
        let manifest = ext.manifest
        let rawPermissions = manifest["permissions"] as? [String] ?? []
        let hostPermissions = (manifest["host_permissions"] as? [String] ?? [])
            + (manifest["manifest_version"] as? Int == 2 ? rawPermissions.filter { $0.contains("://") || $0 == "<all_urls>" } : [])
        var info = fallback ?? [:]
        info["id"] = context.uniqueIdentifier
        info["name"] = ext.displayName ?? manifest["name"] as? String ?? context.uniqueIdentifier
        info["shortName"] = manifest["short_name"] as? String ?? info["name"] as? String ?? context.uniqueIdentifier
        info["version"] = ext.version ?? manifest["version"] as? String ?? ""
        info["description"] = manifest["description"] as? String ?? ""
        info["enabled"] = true
        info["type"] = "extension"
        info["isApp"] = false
        info["installType"] = fallback?["installType"] ?? "normal"
        info["mayDisable"] = true
        info["mayEnable"] = true
        info["offlineEnabled"] = manifest["offline_enabled"] as? Bool ?? false
        info["homepageUrl"] = manifest["homepage_url"] as? String ?? ""
        info["optionsUrl"] = context.optionsPageURL?.absoluteString ?? ""
        // Prefer the source manifest's record: ExtensionCompat adds an internal nativeMessaging
        // entry to the prepared copy, which Chrome's management API should not report as requested.
        info["permissions"] = fallback?["permissions"] ?? rawPermissions.filter { !$0.contains("://") && $0 != "<all_urls>" }
        info["hostPermissions"] = fallback?["hostPermissions"] ?? hostPermissions
        if let versionName = manifest["version_name"] as? String, versionName != (ext.version ?? "") {
            info["versionName"] = versionName
        }
        if let image = ext.icon(for: CGSize(width: 48, height: 48)), let data = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: data),
           let png = bitmap.representation(using: .png, properties: [:]) {
            info["icons"] = [["size": 48, "url": "data:image/png;base64," + png.base64EncodedString()]]
        }
        return info
    }

    private func managementError(_ message: String) -> NSError {
        NSError(domain: "Ark.Extensions.Management", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    func webExtensionController(_ controller: WKWebExtensionController, connectUsing port: WKWebExtension.MessagePort,
                                for extensionContext: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        // Ark's own names, answered in-process: no helper app is started.
        if port.applicationIdentifier == ExtensionWebSocket.portName {
            ExtensionWebSocket.accept(port, for: extensionContext)
            completionHandler(nil)
            return
        }
        completionHandler(Self.noNativeMessaging(port.applicationIdentifier))
    }

    private static func noNativeMessaging(_ name: String?) -> NSError {
        NSError(domain: "Ark.Extensions", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Ark can't reach the app \(name ?? "") from an extension yet."])
    }

    func webExtensionController(_ controller: WKWebExtensionController, didUpdate action: WKWebExtension.Action,
                                forExtensionContext context: WKWebExtensionContext) {
        host?.extensionActionsDidChange()
    }

    func webExtensionController(_ controller: WKWebExtensionController, presentActionPopup action: WKWebExtension.Action,
                                for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        guard let popover = action.popupPopover,
              let anchor = popupAnchor ?? NSApp.keyWindow?.contentView else {
            completionHandler(nil)
            return
        }
        if let popup = action.popupWebView {
            let key = ObjectIdentifier(popup)
            let navigationDelegate = popupNavigationDelegates[key] ?? ExtensionActionPopupNavigationDelegate(owner: self, action: action)
            navigationDelegate.update(action: action)
            popupNavigationDelegates[key] = navigationDelegate
            popup.navigationDelegate = navigationDelegate
        }
        popover.behavior = .transient
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
        completionHandler(nil)
    }

    fileprivate func openPopupLink(_ url: URL?) {
        guard let url,
              !["javascript", "file"].contains(url.scheme?.lowercased() ?? "") else { return }
        let windowID = host?.extensionWindows.first?.id
        _ = host?.openExtensionTab(url: url, windowID: windowID, active: true)
    }
}

/// WebKit's native action popover does not route `_blank` popup links through
/// `createWebViewWith`; handle those links at the exposed popup web view instead.
@available(macOS 15.4, *)
@MainActor
private final class ExtensionActionPopupNavigationDelegate: NSObject, WKNavigationDelegate {
    private weak var owner: WebKitExtensions?
    private var action: WKWebExtension.Action

    init(owner: WebKitExtensions, action: WKWebExtension.Action) {
        self.owner = owner
        self.action = action
    }

    func update(action: WKWebExtension.Action) {
        self.action = action
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard navigationAction.targetFrame == nil else {
            return .allow
        }
        owner?.openPopupLink(navigationAction.request.url)
        action.closePopup()
        return .cancel
    }
}

/// Which extensions may inspect private tabs. None do until the person allows them.
enum WebKitExtensionsPrivacy {
    private static let key = "extensions.allowedInPrivate"

    static func isAllowed(_ id: String) -> Bool {
        (UserDefaults.standard.stringArray(forKey: key) ?? []).contains(id)
    }

    static func set(_ id: String, allowed: Bool) {
        var ids = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        if allowed { ids.insert(id) } else { ids.remove(id) }
        UserDefaults.standard.set(ids.sorted(), forKey: key)
    }
}

/// A Ark window, for extensions.
@available(macOS 15.4, *)
@MainActor
final class ExtensionWindow: NSObject, WKWebExtensionWindow {
    let id: UUID
    private weak var extensions: WebKitExtensions?

    init(id: UUID, extensions: WebKitExtensions) {
        self.id = id
        self.extensions = extensions
    }

    private var info: EngineWindowInfo? { extensions?.info(for: id) }

    func tabs(for context: WKWebExtensionContext) -> [any WKWebExtensionTab] {
        info?.pages.compactMap { $0 as? WebKitPage } ?? []
    }

    func activeTab(for context: WKWebExtensionContext) -> (any WKWebExtensionTab)? { info?.activePage as? WebKitPage }
    func windowType(for context: WKWebExtensionContext) -> WKWebExtension.WindowType { .normal }
    func windowState(for context: WKWebExtensionContext) -> WKWebExtension.WindowState { .normal }
    func isPrivate(for context: WKWebExtensionContext) -> Bool { info?.isPrivate ?? false }
    func frame(for context: WKWebExtensionContext) -> CGRect { info?.frame ?? .null }
    func screenFrame(for context: WKWebExtensionContext) -> CGRect { NSScreen.main?.frame ?? .null }

    func focus(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        extensions?.host?.focusExtensionWindow(id)
        completionHandler(nil)
    }
}

/// A Ark tab, for extensions: its page.
@available(macOS 15.4, *)
extension WebKitPage: WKWebExtensionTab {
    private var extensions: WebKitExtensions? { engine?.webExtensions }
    private var windowInfo: EngineWindowInfo? { extensions?.windowInfo(containing: self) }

    public func window(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        guard let info = windowInfo else { return nil }
        return extensions?.window(info.id)
    }

    public func indexInWindow(for context: WKWebExtensionContext) -> Int {
        windowInfo?.pages.firstIndex { $0 === self } ?? 0
    }

    public func webView(for context: WKWebExtensionContext) -> WKWebView? { webView }
    public func title(for context: WKWebExtensionContext) -> String? { webView.title }
    public func url(for context: WKWebExtensionContext) -> URL? { webView.url }
    public func isLoadingComplete(for context: WKWebExtensionContext) -> Bool { !webView.isLoading }
    public func isSelected(for context: WKWebExtensionContext) -> Bool { windowInfo?.activePage === self }
    public func zoomFactor(for context: WKWebExtensionContext) -> Double { webView.pageZoom }

    public func activate(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        extensions?.host?.activateExtensionTab(self)
        completionHandler(nil)
    }

    public func loadURL(_ url: URL, for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        load(url)
        completionHandler(nil)
    }

    public func close(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        extensions?.host?.closeExtensionTab(self)
        completionHandler(nil)
    }
}
#endif
