#if os(iOS)
import Foundation
import UIKit
import WebKit
import Suggest

extension BrowserState {
    // MARK: Website data

    public func clearHistory() async {
        await profileHistory.clearAll(profileIDs: Set(settings.websiteProfiles.map(\.id) + regularSpaces.compactMap(\.websiteProfileID)))
    }

    /// Forgets cookies and site storage from regular tabs. Private tabs have their own store.
    public func clearWebsiteData() async {
        await WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                                                      modifiedSince: .distantPast)
        for id in Set(settings.websiteProfiles.map(\.id) + regularSpaces.compactMap(\.websiteProfileID)) {
            let store = pool.regularConfiguration(for: id).websiteDataStore
            await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        }
        HTTPCookieStorage.shared.removeCookies(since: .distantPast)
        // The open page still looks signed in until it's loaded again.
        if currentTab?.isPrivate == false { reload() }
    }

    // MARK: Spaces

    func websiteProfileID(for tab: BrowserTab) -> UUID? {
        guard !tab.isPrivate else { return nil }
        return spaces.first { $0.allTabs.contains { $0 === tab } }?.websiteProfileID
    }

    public func assignWebsiteProfile(_ id: UUID?, to space: Space) {
        guard regularSpaces.contains(where: { $0 === space }), space.websiteProfileID != id,
              id.map({ id in settings.websiteProfiles.contains { $0.id == id } }) ?? true else { return }
        for tab in space.allTabs {
            cancelPrompts(for: tab.id)
            cancelPageCapture(of: tab)
            pool.resetSession(for: tab.id)
            tab.interactionState = nil
            tab.websiteSessionProfileID = nil
            tab.loadError = nil
            tab.canGoBack = false
            tab.canGoForward = false
            tab.isLoading = false
            tab.isAwaitingFirstPaint = false
            tab.isChromeCompact = false
            tab.pageBackground = nil
            discardTabThumbnail(tab.id)
        }
        if currentSpace === space {
            readerArticle = nil
            siteStyleHost = nil
            isTabSwitcherPresented = false
            isRecentTabPreviewsPresented = false
            isNewTabSheetPresented = false
        }
        space.websiteProfileID = id
        scheduleSave()
    }

    public func renameWebsiteProfile(_ id: UUID, to name: String) {
        guard let index = settings.websiteProfiles.firstIndex(where: { $0.id == id }) else { return }
        var profile = settings.websiteProfiles[index]
        guard profile.rename(to: name) else { return }
        settings.websiteProfiles[index] = profile
    }

    public func deleteWebsiteProfile(_ id: UUID) async {
        guard settings.websiteProfiles.contains(where: { $0.id == id }) else { return }
        let affectedSpaces = regularSpaces.filter { $0.websiteProfileID == id }
        let affectedTabs = affectedSpaces.flatMap(\.allTabs)
        for space in affectedSpaces { assignWebsiteProfile(nil, to: space) }
        for tab in affectedTabs {
            tab.interactionState = nil
            tab.websiteSessionProfileID = nil
        }
        removeWebsiteProfileReferences(id)
        settings.websiteProfiles.removeAll { $0.id == id }
        await pool.deleteWebsiteDataStore(for: id)
        await profileHistory.deleteProfile(id)
        scheduleSave()
    }

    public func addSpace() {
        let used = Set(spaces.map(\.colorIndex))
        let color = (0..<6).first { !used.contains($0) } ?? spaces.count
        let space = Space(name: "Space \(regularSpaces.count + 1)", symbol: "circle.fill", colorIndex: color)
        // Private stays at the end.
        spaces.insert(space, at: spaces.firstIndex { $0.isPrivate } ?? spaces.endIndex)
        scheduleSave()
    }

    @discardableResult
    public func importSpaceLinks(_ archive: SpaceLinkArchive) -> Space {
        let profileID = archive.makeImportedWebsiteProfile(in: &settings.websiteProfiles)
        let space = archive.makeSpace(colorIndex: regularSpaces.count, websiteProfileID: profileID)
        spaces.insert(space, at: regularSpaces.count)
        scheduleSave()
        return space
    }

    public func websiteProfileName(for space: Space) -> String? {
        guard let profileID = space.websiteProfileID else { return nil }
        return settings.websiteProfiles.first { $0.id == profileID }?.name
    }

    public func deleteSpace(_ space: Space) {
        if space.isPrivate { closePrivateSpace(); return }
        guard regularSpaces.count > 1, let i = spaces.firstIndex(where: { $0.id == space.id }) else { return }
        space.allTabs.forEach { pool.remove($0.id) }
        spaces.remove(at: i)
        if selectedSpaceID == space.id { selectedSpaceID = regularSpaces[0].id }
        if settings.externalLinksSpaceID == space.id { settings.externalLinksSpaceID = nil }
        settings.linkRoutingRules.removeAll { $0.spaceID == space.id }
        scheduleSave()
    }

    /// A link opened from another app (once this is the default browser).
    public func openExternal(_ url: URL) {
        // Never into Private: links from other apps belong with your normal tabs.
        let target = routedSpace(for: url) ?? regularSpaces.first { $0.id == settings.externalLinksSpaceID } ?? regularTargetSpace
        isNewTabSheetPresented = false
        newTab(url: url, in: target, source: .link)
    }

    func routedSpace(for url: URL) -> Space? {
        guard settings.linkRoutingEnabled, !settings.linkRoutingRules.isEmpty else { return nil }
        let spaces = regularSpaces
        let rule = RouteRule.bestMatch(for: url, rules: settings.linkRoutingRules, destinations: Set(spaces.map(\.id)))
        return rule.flatMap { match in spaces.first { $0.id == match.spaceID } }
    }

    // MARK: Archive

    public func restoreFromArchive(_ tab: BrowserTab) {
        archive.removeAll { $0.id == tab.id }
        restoreTabInCurrentProfile(tab)
    }

    public func clearArchive() {
        archive.removeAll()
        scheduleSave()
    }

    // MARK: Saved sites

    public func isSaved(_ url: URL) -> Bool {
        let key = URLNormalizer.key(for: url)
        return saved.contains { URLNormalizer.key(for: $0.url) == key }
    }

    /// The page menu's Save / Unsave for the current page. Keeps a picture of the page for the list.
    public func toggleSavedForCurrentTab() {
        guard let tab = currentTab, let url = tab.url else { return }
        let key = URLNormalizer.key(for: url)
        if let existing = saved.first(where: { URLNormalizer.key(for: $0.url) == key }) {
            removeSaved(existing)
            showToast("Removed from Saved")
            return
        }
        let site = SavedSite(url: url, title: tab.displayTitle)
        saved.insert(site, at: 0)
        if let image = pool.existingSession(for: tab.id)?.renderThumbnail() ?? thumbnails[tab.id] {
            thumbnails[site.id] = image
            // A private page's picture stays in memory, like private tabs' own.
            if !tab.isPrivate, let thumbnailStore, let data = image.jpegData(compressionQuality: 0.7) {
                let id = site.id
                Task.detached(priority: .utility) { thumbnailStore.save(data, for: id) }
            }
        }
        showToast("Saved")
        scheduleSave()
    }

    public func removeSaved(_ site: SavedSite) {
        saved.removeAll { $0.id == site.id }
        thumbnails[site.id] = nil
        if let thumbnailStore {
            let id = site.id
            Task.detached(priority: .utility) { thumbnailStore.remove(id) }
        }
        scheduleSave()
    }

    // MARK: Favourites

    public func isFavorite(_ url: URL) -> Bool {
        let key = URLNormalizer.key(for: url)
        return favorites.contains { URLNormalizer.key(for: $0.url) == key }
    }

    public func addFavorite(url: URL, title: String) {
        guard !isFavorite(url) else { return }
        favorites.append(Favorite(url: url, title: title, order: (favorites.map(\.order).max() ?? -1) + 1))
        Task { await profileHistory.store(for: currentSpace.websiteProfileID).setBookmarked(url, true) }
        scheduleSave()
    }

    public func removeFavorite(_ fav: Favorite) {
        favorites.removeAll { $0.id == fav.id }
        Task { await profileHistory.store(for: currentSpace.websiteProfileID).setBookmarked(fav.url, false) }
        scheduleSave()
    }

    public func renameFavorite(_ fav: Favorite, to name: String) {
        guard let i = favorites.firstIndex(where: { $0.id == fav.id }) else { return }
        favorites[i].customName = name.isEmpty ? nil : name
        scheduleSave()
    }

    public func moveFavorites(fromOffsets: IndexSet, toOffset: Int) {
        var sorted = favorites.sorted { $0.order < $1.order }
        sorted.move(fromOffsets: fromOffsets, toOffset: toOffset)
        for i in sorted.indices { sorted[i].order = i }
        favorites = sorted
        scheduleSave()
    }
}
#endif
