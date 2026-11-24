import Foundation
import CoreGraphics
import Observation
import Suggest

@MainActor @Observable
public final class BrowserTab: Identifiable {
    public let id: UUID
    public var url: URL?
    public var title: String
    public var isPinned: Bool
    public var lastActive: Date
    /// WKWebView.interactionState (back/forward list + scroll), saved when the web view is evicted.
    public var interactionState: Data?
    public var websiteSessionProfileID: UUID?
    public var isPrivate: Bool
    /// Set when the tab was opened from a favourite: it belongs to that favourite's tile and stays
    /// out of the Today list.
    public var favoriteID: UUID?
    /// The Mac window this Today tab belongs to, so each window keeps its own Today list (like Arc).
    /// Pinned and favourite tabs ignore it: every window shares those. Nil, or a window that isn't
    /// open, means any window may take the tab. iOS has one window and ignores it.
    public var windowKey: UUID?
    /// A name you gave the tab (double-click it in the sidebar). Shown instead of the page's title.
    public var customTitle: String?
    public internal(set) var pinFolderID: UUID?

    // Live state mirrored from the web view (not persisted).
    public var estimatedProgress: Double = 0
    public var isLoading = false
    public var canGoBack = false
    public var canGoForward = false
    /// Bottom bar collapsed to a small pill because the page is being scrolled down.
    public var isChromeCompact = false
    /// Set when the last load failed; the page area shows an error page with Retry.
    public var loadError: LoadError?
    /// Whether the current page was requested as the desktop site.
    public var isDesktopSite = false
    /// The colour WebKit shows beyond the page's edges. Nil until the page says.
    public var pageBackground: CGColor?
    /// A new web view hasn't drawn its page yet, so show the tab's last picture over it.
    public var isAwaitingFirstPaint = false
    /// The page has the camera or microphone on: the tab is in a call. Nil otherwise.
    public var call: TabCall?
    /// The page's zoom (1 = actual size), for the address bar's zoom badge. The engine's own value
    /// can't be observed, so the Mac app keeps this one in step whenever it zooms.
    public var pageZoom: Double = 1

    public init(id: UUID = UUID(), url: URL?, title: String = "", isPinned: Bool = false,
                lastActive: Date = .now, interactionState: Data? = nil, isPrivate: Bool = false) {
        self.id = id
        self.url = url
        self.title = title
        self.isPinned = isPinned
        self.lastActive = lastActive
        self.interactionState = interactionState
        self.isPrivate = isPrivate
    }

    public var displayTitle: String {
        if let customTitle, !customTitle.isEmpty { return customTitle }
        if !title.isEmpty { return title }
        if let url { return URLNormalizer.displayHost(url) }
        return "New Tab"
    }
}

/// What a tab in a call is using, for the badge that leads back to it.
public struct TabCall: Equatable, Sendable {
    /// The camera is on.
    public var camera: Bool
    /// The microphone is on (false when it's muted or off).
    public var microphone: Bool

    public init(camera: Bool, microphone: Bool) {
        self.camera = camera
        self.microphone = microphone
    }
}

@MainActor @Observable
public final class Space: Identifiable {
    public let id: UUID
    public var name: String
    /// SF Symbol name
    public var symbol: String
    /// Index into the app's space colour palette.
    public var colorIndex: Int
    /// The Mac's space theme, on top of `colorIndex` (the iPhone app keeps to the palette). Nil fields fall
    /// back to the palette colour's defaults.
    /// The colour's hue in degrees, 0...360.
    public var themeHue: Double?
    /// How light or dark the colour sits, 0 (lighter) to 1 (darker), within the window's light or dark range.
    public var themeShade: Double?
    /// "light" or "dark" keeps the space's whole window in that appearance. Nil follows Ark's setting.
    public var appearance: String?
    public var pinned: [BrowserTab]
    public internal(set) var pinFolders: [PinFolder] = []
    @ObservationIgnored var liveFolderRefreshTimes: [UUID: Date] = [:]
    @ObservationIgnored var refreshingLiveFolderIDs: Set<UUID> = []
    public var today: [BrowserTab]
    public var selectedTabID: UUID?
    public var websiteProfileID: UUID?
    /// A shared Space was removed elsewhere while this device still had local Today tabs open.
    /// The retained Space stays on this device and is omitted from browser sync.
    public var isSyncLocalOnly = false
    public internal(set) var splitPair: TabSplitPair?
    public var isSidebarOpen: Bool
    /// The Private space: shows in the spaces list only while it has tabs, and is never saved.
    public let isPrivate: Bool

    public init(id: UUID = UUID(), name: String, symbol: String = "circle.fill", colorIndex: Int = 0,
                pinned: [BrowserTab] = [], today: [BrowserTab] = [], selectedTabID: UUID? = nil, isSidebarOpen: Bool = true,
                isPrivate: Bool = false, isSyncLocalOnly: Bool = false) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.colorIndex = colorIndex
        self.pinned = pinned
        self.today = today
        self.selectedTabID = selectedTabID
        self.isSidebarOpen = isSidebarOpen
        self.isPrivate = isPrivate
        self.isSyncLocalOnly = isSyncLocalOnly
    }

    public var allTabs: [BrowserTab] { pinned + today }

    /// Today's tabs as the sidebar lists them: without the ones a favourite tile holds.
    public var listedToday: [BrowserTab] { today.filter { $0.favoriteID == nil } }

    public var selectedTab: BrowserTab? {
        allTabs.first { $0.id == selectedTabID }
    }

    public func recentTabs(limit: Int) -> [BrowserTab] {
        guard limit > 0 else { return [] }
        let selected = selectedTabID
        return Array(allTabs.sorted { left, right in
            if (left.id == selected) != (right.id == selected) { return left.id == selected }
            return left.lastActive > right.lastActive
        }.prefix(limit))
    }

    public var splitCandidates: [BrowserTab] {
        guard let current = selectedTab, isSplittable(current) else { return [] }
        return allTabs.filter { $0.id != current.id && isSplittable($0) }
    }

    public var activeSplitTabs: (BrowserTab, BrowserTab)? {
        guard let members = activeSplitMembers, members.count == 2 else { return nil }
        return (members[0], members[1])
    }

    public var activeSplitMembers: [BrowserTab]? {
        guard let pair = splitPair, let selectedTabID, pair.contains(selectedTabID) else { return nil }
        return splitTabs(for: pair)
    }

    public var additionalSplitCandidates: [BrowserTab] {
        guard let split = splitPair, activeSplitMembers != nil, split.tabs.count < TabSplitPair.maxPanes else { return [] }
        return splitCandidates.filter { !split.contains($0.id) }
    }

    @discardableResult
    public func splitWith(_ tab: BrowserTab) -> Bool {
        guard let current = selectedTab, splitCandidates.contains(where: { $0 === tab }) else { return false }
        splitPair = TabSplitPair(first: current.id, second: tab.id)
        return true
    }

    public func separateTabs() { splitPair = nil }

    @discardableResult
    public func addToSplit(_ tab: BrowserTab) -> Bool {
        guard var split = splitPair, additionalSplitCandidates.contains(where: { $0 === tab }) else { return false }
        split.setTabs(split.tabs + [tab.id])
        splitPair = split
        return true
    }

    func detachSplitMember(_ id: UUID) -> UUID? {
        guard var split = splitPair, let index = split.tabs.firstIndex(of: id) else { return nil }
        var survivors = split.tabs
        survivors.remove(at: index)
        let neighbor = activeSplitMembers == nil ? nil : survivors[min(index, survivors.count - 1)]
        splitPair = nil
        if survivors.count >= 2 {
            var shares = split.shares
            shares.remove(at: index)
            let total = shares.reduce(0, +)
            split.setTabs(survivors)
            split.setShares(shares.map { $0 / total })
            if splitTabs(for: split) != nil { splitPair = split }
        }
        return neighbor
    }

    public func resizeSplit(to fraction: Double) {
        guard fraction.isFinite, activeSplitTabs != nil else { return }
        splitPair?.fraction = min(0.75, max(0.25, fraction))
    }

    public func resizeSplit(after index: Int, by delta: Double) {
        guard var split = splitPair, activeSplitMembers != nil else { return }
        split.setShares(split.resizedShares(after: index, by: delta))
        splitPair = split
    }

    private func isSplittable(_ tab: BrowserTab) -> Bool {
        guard !isPrivate, !tab.isPrivate, tab.favoriteID == nil,
              let scheme = tab.url?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    private func splitTabs(for pair: TabSplitPair) -> [BrowserTab]? {
        let ids = pair.tabs
        guard ids.count <= TabSplitPair.maxPanes, Set(ids).count == ids.count else { return nil }
        let members = ids.compactMap(splitMember)
        return members.count == ids.count ? members : nil
    }

    private func splitMember(_ id: UUID) -> BrowserTab? {
        let tab = pinned.first { $0.id == id } ?? today.first { $0.id == id }
        guard let tab, isSplittable(tab) else { return nil }
        return tab
    }
}

public struct TabSplitPair: Codable, Equatable, Sendable {
    static let maxPanes = 4
    public internal(set) var first: UUID
    public internal(set) var second: UUID
    public internal(set) var fraction: Double = 0.5
    private var additional: [UUID]?
    private var customShares: [Double]?

    init(first: UUID, second: UUID, fraction: Double = 0.5) {
        self.first = first
        self.second = second
        self.fraction = fraction
    }

    public var tabs: [UUID] { [first, second] + (additional ?? []) }
    private var minimumShare: Double { tabs.count > 2 ? 0.16 : 0.25 }

    public var shares: [Double] {
        let count = tabs.count
        if count == 2 {
            let first = min(0.75, max(0.25, fraction.isFinite ? fraction : 0.5))
            return [first, 1 - first]
        }
        guard let customShares, customShares.count == count,
              customShares.allSatisfy({ $0.isFinite && $0 >= minimumShare - 0.0001 }),
              abs(customShares.reduce(0, +) - 1) < 0.0001 else {
            return Array(repeating: 1 / Double(count), count: count)
        }
        return customShares
    }

    public func contains(_ id: UUID) -> Bool { tabs.contains(id) }

    public func resizedShares(after index: Int, by delta: Double) -> [Double] {
        var shares = self.shares
        guard index >= 0, index + 1 < shares.count, delta.isFinite else { return shares }
        let change = min(shares[index + 1] - minimumShare, max(minimumShare - shares[index], delta))
        shares[index] += change
        shares[index + 1] -= change
        return shares
    }

    mutating func setTabs(_ tabs: [UUID]) {
        first = tabs[0]
        second = tabs[1]
        additional = tabs.count > 2 ? Array(tabs.dropFirst(2)) : nil
        fraction = 0.5
        customShares = nil
    }

    mutating func setShares(_ shares: [Double]) {
        if shares.count == 2 {
            fraction = min(0.75, max(0.25, shares[0]))
            customShares = nil
        } else {
            customShares = shares
        }
    }
}

// MARK: - Settings

public struct WebsiteProfile: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public private(set) var name: String

    public init?(name: String) {
        self.init(id: UUID(), name: name)
    }

    public init?(id: UUID, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        self.id = id
        self.name = String(trimmed.prefix(80))
    }

    @discardableResult
    public mutating func rename(to name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        self.name = String(trimmed.prefix(80))
        return true
    }
}

public struct BrowserSettings: Codable, Equatable, Sendable {
    public var searchEngine: SearchEngine = .google
    /// Send typed text to the search engine for suggestions. Off = local suggestions only.
    public var remoteSuggestions = true
    /// Today tabs untouched for this many hours move to the archive.
    public var archiveAfterHours: Double = 12
    /// Mac releases ready, inactive WebViews after this many minutes. Zero disables idle unloading.
    public var unloadIdlePagesAfterMinutes: Double = 30
    /// Block ads and trackers with the built-in content rule list.
    public var blockContent = true
    /// Where links from other apps open.
    public var externalLinksSpaceID: UUID?
    public var linkRoutingEnabled = false
    public var linkRoutingRules: [RouteRule] = []
    public var websiteProfiles: [WebsiteProfile] = []
    /// Ask for desktop sites on the inner display (like iPad Safari) and mobile sites when folded.
    public var desktopSitesWhenUnfolded = true
    /// Per-site "Request Desktop/Mobile Site" choices, keyed by host. true = desktop.
    public var siteDesktopOverrides: [String: Bool] = [:]
    /// Remembered camera/microphone/motion answers, keyed by host then permission.
    public var sitePermissions: [String: [String: Bool]] = [:]
    /// Click "Reject" on cookie banners automatically (DuckDuckGo's autoconsent).
    public var declineCookieBanners = true
    /// Strip tracking parameters (utm_*, fbclid…) from links before they load.
    public var cleanLinks = true
    /// Which filter lists feed the ad/tracker blocker, when `blockContent` is on.
    public var filterGroups: Set<FilterGroup> = Set(FilterGroup.allCases)
    /// Sites where blocking (ads, trackers, cookie banners) is switched off. Hosts.
    public var blockingDisabledHosts: Set<String> = []
    /// Exact leaf certificates the user chose to trust, keyed by normalized host and port.
    public var certificateExceptions: [String: String] = [:]

    public init() {}

    /// True when the user turned blockers off for this host (or a parent domain of it).
    public func blockingDisabled(for host: String?) -> Bool {
        guard let host = host?.lowercased(), !host.isEmpty else { return false }
        return blockingDisabledHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    public init(from decoder: any Decoder) throws {
        // Decode field by field so settings saved by older builds still load.
        let c = try decoder.container(keyedBy: CodingKeys.self)
        searchEngine = try c.decodeIfPresent(SearchEngine.self, forKey: .searchEngine) ?? .google
        remoteSuggestions = try c.decodeIfPresent(Bool.self, forKey: .remoteSuggestions) ?? true
        archiveAfterHours = try c.decodeIfPresent(Double.self, forKey: .archiveAfterHours) ?? 12
        unloadIdlePagesAfterMinutes = try c.decodeIfPresent(Double.self, forKey: .unloadIdlePagesAfterMinutes) ?? 30
        blockContent = try c.decodeIfPresent(Bool.self, forKey: .blockContent) ?? true
        externalLinksSpaceID = try c.decodeIfPresent(UUID.self, forKey: .externalLinksSpaceID)
        linkRoutingEnabled = try c.decodeIfPresent(Bool.self, forKey: .linkRoutingEnabled) ?? false
        linkRoutingRules = try c.decodeIfPresent([RouteRule].self, forKey: .linkRoutingRules) ?? []
        websiteProfiles = try c.decodeIfPresent([WebsiteProfile].self, forKey: .websiteProfiles) ?? []
        desktopSitesWhenUnfolded = try c.decodeIfPresent(Bool.self, forKey: .desktopSitesWhenUnfolded) ?? true
        siteDesktopOverrides = try c.decodeIfPresent([String: Bool].self, forKey: .siteDesktopOverrides) ?? [:]
        sitePermissions = try c.decodeIfPresent([String: [String: Bool]].self, forKey: .sitePermissions) ?? [:]
        declineCookieBanners = try c.decodeIfPresent(Bool.self, forKey: .declineCookieBanners) ?? true
        cleanLinks = try c.decodeIfPresent(Bool.self, forKey: .cleanLinks) ?? true
        filterGroups = try c.decodeIfPresent(Set<FilterGroup>.self, forKey: .filterGroups) ?? Set(FilterGroup.allCases)
        blockingDisabledHosts = try c.decodeIfPresent(Set<String>.self, forKey: .blockingDisabledHosts) ?? []
        certificateExceptions = try c.decodeIfPresent([String: String].self, forKey: .certificateExceptions) ?? [:]
    }
}

/// One content blocker. WebKit caps each at 150,000 rules, so the filter lists are split
/// across several, the way AdGuard for iOS does it.
public enum FilterGroup: String, Codable, CaseIterable, Sendable, Identifiable {
    case ads, privacy, annoyances
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .ads: "Ads"
        case .privacy: "Trackers"
        case .annoyances: "Annoyances"
        }
    }

    public var detail: String {
        switch self {
        case .ads: "AdGuard Base and Mobile Ads filters"
        case .privacy: "AdGuard Tracking Protection and Social Media filters"
        case .annoyances: "Cookie notices, pop-ups, app banners and widgets"
        }
    }
}

/// Why a page couldn't load, shown in place of the page.
public struct LoadError: Equatable, Sendable {
    public enum Kind: Sendable { case offline, notFound, timedOut, insecure, other }
    public let url: URL?
    public let kind: Kind
    public let detail: String
    public let certificateFingerprint: String?

    public var title: String {
        switch kind {
        case .offline: "You're offline"
        case .notFound: "Can't find this site"
        case .timedOut: "The site took too long to respond"
        case .insecure: "This connection isn't private"
        case .other: "Couldn't open this page"
        }
    }

    public var symbol: String {
        switch kind {
        case .offline: "wifi.slash"
        case .notFound: "questionmark.app.dashed"
        case .timedOut: "clock.badge.exclamationmark"
        case .insecure: "lock.slash"
        case .other: "exclamationmark.triangle"
        }
    }

    /// Certificate problems can offer a one-certificate exception when WebKit identified it.
    public var canRetry: Bool { kind != .insecure }
    public var canVisitAnyway: Bool { kind == .insecure && certificateFingerprint != nil }

    public init(url: URL?, error: NSError) {
        self.url = url
        certificateFingerprint = error.userInfo["ArkCertificateFingerprint"] as? String
        switch (error.domain, error.code) {
        case (NSURLErrorDomain, NSURLErrorNotConnectedToInternet), (NSURLErrorDomain, NSURLErrorNetworkConnectionLost),
             (NSURLErrorDomain, NSURLErrorDataNotAllowed), (NSURLErrorDomain, NSURLErrorInternationalRoamingOff):
            kind = .offline
        case (NSURLErrorDomain, NSURLErrorCannotFindHost), (NSURLErrorDomain, NSURLErrorDNSLookupFailed),
             (NSURLErrorDomain, NSURLErrorCannotConnectToHost):
            kind = .notFound
        case (NSURLErrorDomain, NSURLErrorTimedOut):
            kind = .timedOut
        case (NSURLErrorDomain, NSURLErrorSecureConnectionFailed), (NSURLErrorDomain, NSURLErrorServerCertificateHasBadDate),
             (NSURLErrorDomain, NSURLErrorServerCertificateUntrusted), (NSURLErrorDomain, NSURLErrorServerCertificateHasUnknownRoot),
             (NSURLErrorDomain, NSURLErrorServerCertificateNotYetValid), (NSURLErrorDomain, NSURLErrorClientCertificateRejected),
             (NSURLErrorDomain, NSURLErrorClientCertificateRequired):
            kind = .insecure
        default:
            kind = .other
        }
        detail = error.localizedDescription
    }

    /// Cancellations and "frame load interrupted" (a download took over) aren't failures.
    public static func isIgnorable(_ error: NSError) -> Bool {
        (error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled)
            || (error.domain == "WebKitErrorDomain" && [102, 204].contains(error.code))
    }
}

// MARK: - Saved sites

/// A page put aside to read later, from the page menu's Save. A flat list, newest first, like the
/// saved posts in a social app. No folders.
public struct SavedSite: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var url: URL
    public var title: String
    public var savedAt: Date

    public init(id: UUID = UUID(), url: URL, title: String, savedAt: Date = .now) {
        self.id = id
        self.url = url
        self.title = title
        self.savedAt = savedAt
    }
}

// MARK: - Codable snapshot for persistence

/// The saved form of a tab. Shared by the iOS and Mac apps, so the formats can sync later.
public struct TabRecord: Codable, Sendable {
    public var id: UUID, url: URL?, title: String, isPinned: Bool, lastActive: Date, interactionState: Data?
    /// Missing in state saved before favourites owned their tabs.
    public var favoriteID: UUID? = nil
    /// Missing in state saved before each Mac window had its own Today tabs.
    public var windowKey: UUID? = nil
    /// Missing in state saved before tabs could be renamed.
    public var customTitle: String? = nil
    public var pinFolderID: UUID? = nil
    public var websiteSessionProfileID: UUID? = nil
}

public struct SpaceRecord: Codable, Sendable {
    public var id: UUID, name: String, symbol: String, colorIndex: Int
    public var pinned: [TabRecord], today: [TabRecord], selectedTabID: UUID?, isSidebarOpen: Bool
    /// Missing in state saved before Mac space themes (see `Space`).
    public var themeHue: Double? = nil
    public var themeShade: Double? = nil
    public var appearance: String? = nil
    public var pinFolders: [PinFolder]? = nil
    public var splitPair: TabSplitPair? = nil
    public var websiteProfileID: UUID? = nil
    public var isSyncLocalOnly = false

    private enum CodingKeys: String, CodingKey {
        case id, name, symbol, colorIndex, pinned, today, selectedTabID, isSidebarOpen
        case themeHue, themeShade, appearance, pinFolders, splitPair, websiteProfileID, isSyncLocalOnly
    }

    public init(id: UUID, name: String, symbol: String, colorIndex: Int,
                pinned: [TabRecord], today: [TabRecord], selectedTabID: UUID?, isSidebarOpen: Bool,
                themeHue: Double? = nil, themeShade: Double? = nil, appearance: String? = nil,
                pinFolders: [PinFolder]? = nil, splitPair: TabSplitPair? = nil,
                websiteProfileID: UUID? = nil, isSyncLocalOnly: Bool = false) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.colorIndex = colorIndex
        self.pinned = pinned
        self.today = today
        self.selectedTabID = selectedTabID
        self.isSidebarOpen = isSidebarOpen
        self.themeHue = themeHue
        self.themeShade = themeShade
        self.appearance = appearance
        self.pinFolders = pinFolders
        self.splitPair = splitPair
        self.websiteProfileID = websiteProfileID
        self.isSyncLocalOnly = isSyncLocalOnly
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        symbol = try values.decode(String.self, forKey: .symbol)
        colorIndex = try values.decode(Int.self, forKey: .colorIndex)
        pinned = try values.decodeIfPresent([TabRecord].self, forKey: .pinned) ?? []
        today = try values.decodeIfPresent([TabRecord].self, forKey: .today) ?? []
        selectedTabID = try values.decodeIfPresent(UUID.self, forKey: .selectedTabID)
        isSidebarOpen = try values.decodeIfPresent(Bool.self, forKey: .isSidebarOpen) ?? true
        themeHue = try values.decodeIfPresent(Double.self, forKey: .themeHue)
        themeShade = try values.decodeIfPresent(Double.self, forKey: .themeShade)
        appearance = try values.decodeIfPresent(String.self, forKey: .appearance)
        pinFolders = try values.decodeIfPresent([PinFolder].self, forKey: .pinFolders)
        splitPair = try values.decodeIfPresent(TabSplitPair.self, forKey: .splitPair)
        websiteProfileID = try values.decodeIfPresent(UUID.self, forKey: .websiteProfileID)
        isSyncLocalOnly = try values.decodeIfPresent(Bool.self, forKey: .isSyncLocalOnly) ?? false
    }
}

public struct BrowserSnapshot: Codable, Sendable {
    public var spaces: [SpaceRecord]
    public var selectedSpaceID: UUID?
    public var favorites: [Favorite]
    /// Profile-scoped favorites. Missing in older snapshots; their global favorites
    /// are migrated into the Default profile when loaded.
    public var profileFavorites: [String: [Favorite]]?
    public var archive: [TabRecord]
    public var settings: BrowserSettings?
    /// Missing in state saved before Saved Sites existed.
    public var saved: [SavedSite]?

    public init(spaces: [SpaceRecord], selectedSpaceID: UUID?, favorites: [Favorite], archive: [TabRecord],
                settings: BrowserSettings?, saved: [SavedSite]?, profileFavorites: [String: [Favorite]]? = nil) {
        self.spaces = spaces
        self.selectedSpaceID = selectedSpaceID
        self.favorites = favorites
        self.profileFavorites = profileFavorites
        self.archive = archive
        self.settings = settings
        self.saved = saved
    }
}

/// Stable snapshot keys for profile-scoped favorites; nil is the legacy Default profile.
public enum FavoriteProfileKey {
    public static let `default` = "default"
    public static func key(for profileID: UUID?) -> String { profileID?.uuidString ?? Self.default }
}

extension BrowserTab {
    public var record: TabRecord {
        TabRecord(id: id, url: url, title: title, isPinned: isPinned, lastActive: lastActive,
                  interactionState: interactionState, favoriteID: favoriteID,
                  windowKey: isPinned || favoriteID != nil ? nil : windowKey, customTitle: customTitle,
                  pinFolderID: isPinned ? pinFolderID : nil,
                  websiteSessionProfileID: websiteSessionProfileID)
    }
    public convenience init(_ r: TabRecord) {
        self.init(id: r.id, url: r.url, title: r.title, isPinned: r.isPinned,
                  lastActive: r.lastActive, interactionState: r.interactionState)
        favoriteID = r.favoriteID
        windowKey = r.windowKey
        customTitle = r.customTitle
        pinFolderID = r.isPinned ? r.pinFolderID : nil
        websiteSessionProfileID = r.websiteSessionProfileID
    }
}

extension Space {
    public var record: SpaceRecord {
        SpaceRecord(id: id, name: name, symbol: symbol, colorIndex: colorIndex,
                    pinned: pinned.map(\.record),
                    today: today.filter { !$0.isPrivate }.map(\.record),
                    selectedTabID: selectedTabID, isSidebarOpen: isSidebarOpen,
                    themeHue: themeHue, themeShade: themeShade,
                    appearance: appearance,
                    pinFolders: pinFolders.isEmpty ? nil : pinFolders,
                    splitPair: splitPair, websiteProfileID: isPrivate ? nil : websiteProfileID,
                    isSyncLocalOnly: isSyncLocalOnly)
    }
    public convenience init(_ r: SpaceRecord) {
        self.init(id: r.id, name: r.name, symbol: r.symbol, colorIndex: r.colorIndex,
                  pinned: r.pinned.map(BrowserTab.init), today: r.today.map(BrowserTab.init),
                  selectedTabID: r.selectedTabID, isSidebarOpen: r.isSidebarOpen,
                  isSyncLocalOnly: r.isSyncLocalOnly)
        themeHue = r.themeHue
        themeShade = r.themeShade
        appearance = r.appearance
        websiteProfileID = r.websiteProfileID
        restorePinFolders(r.pinFolders ?? [])
        if var pair = r.splitPair, splitTabs(for: pair) != nil {
            pair.setShares(pair.shares)
            splitPair = pair
        }
    }
}
