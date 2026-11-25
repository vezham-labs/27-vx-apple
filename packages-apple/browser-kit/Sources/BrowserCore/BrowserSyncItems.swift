import Foundation
import Suggest

/// The stable, privacy-filtered projection of a browser snapshot that Ark can
/// exchange between devices. Open Today tabs, their WebKit interaction state,
/// history, archive, downloads, and site permission grants stay on-device.
public enum BrowserSyncItems {
    private struct DeviceTab: Codable, Sendable {
        var id: UUID
        var title: String
        var url: URL
    }

    private struct DeviceSpace: Codable, Sendable {
        var id: UUID
        var name: String
        var tabs: [DeviceTab]
    }

    private struct DeviceTabs: Codable, Sendable {
        var deviceID: UUID
        var deviceName: String
        var sharing: Bool
        var updatedAt: Date
        var spaces: [DeviceSpace]
    }

    private struct SyncedSpace: Codable, Sendable {
        var id: UUID
        var name: String
        var symbol: String
        var colorIndex: Int
        var themeHue: Double?
        var themeShade: Double?
        var appearance: String?
        var websiteProfileID: UUID?
    }

    private struct SyncedPin: Codable, Sendable {
        var id: UUID
        var url: URL?
        var homeURL: URL?
        var title: String
        var customTitle: String?
        var favoriteID: UUID?
        var folderID: UUID?
        var websiteProfileID: UUID?
    }

    private struct SyncedFavorite: Codable, Sendable {
        var id: UUID
        var url: URL
        var title: String
        var customName: String?
    }

    private struct SyncedFolder: Codable, Sendable {
        var id: UUID
        var name: String
        var parentID: UUID?
        var feedSource: URL?
        var feedTitle: String?
    }

    private struct SyncedProfile: Codable, Sendable {
        var id: UUID
        var name: String
    }

    /// Creates keyed values suitable for `BrowserSyncMerge`. The stable IDs
    /// allow separate edits to different Spaces, pins, folders, and favorites
    /// to merge without replacing an entire snapshot.
    public static func values(from snapshot: BrowserSnapshot) -> [String: String] {
        var values: [String: String] = [:]
        let spaces = snapshot.spaces.filter { !$0.isSyncLocalOnly }
        let localOnlyProfileIDs = Set(snapshot.spaces.filter(\.isSyncLocalOnly).compactMap(\.websiteProfileID))
        values["spaces:order"] = BrowserSyncMerge.text(spaces.map { $0.id.uuidString })

        for space in spaces {
            let id = space.id.uuidString
            let metadata = SyncedSpace(id: space.id, name: space.name, symbol: space.symbol,
                                       colorIndex: space.colorIndex, themeHue: space.themeHue,
                                       themeShade: space.themeShade, appearance: space.appearance,
                                       websiteProfileID: space.websiteProfileID)
            values["space:\(id)"] = BrowserSyncMerge.text(metadata)

            let pins = space.pinned.filter { isShareable($0.url) }
            values["pins:order:\(id)"] = BrowserSyncMerge.text(pins.map { $0.id.uuidString })
            for pin in pins {
                let item = SyncedPin(id: pin.id, url: pin.url, homeURL: pin.pinnedHomeURL, title: pin.title,
                                     customTitle: pin.customTitle, favoriteID: pin.favoriteID,
                                     folderID: pin.pinFolderID, websiteProfileID: pin.websiteSessionProfileID)
                values["pin:\(id):\(pin.id.uuidString)"] = BrowserSyncMerge.text(item)
            }

            let folders = space.pinFolders ?? []
            values["folders:order:\(id)"] = BrowserSyncMerge.text(folders.map { $0.id.uuidString })
            for folder in folders {
                let source = folder.feed.flatMap { safeWebURL($0.source) }
                let item = SyncedFolder(id: folder.id, name: folder.name, parentID: folder.parentID,
                                        feedSource: source, feedTitle: source == nil ? nil : folder.feed?.title)
                values["folder:\(id):\(folder.id.uuidString)"] = BrowserSyncMerge.text(item)
            }
        }

        let profileFavorites = snapshot.profileFavorites ?? [FavoriteProfileKey.default: snapshot.favorites]
        for (profile, favorites) in profileFavorites where !localOnlyProfileIDs.contains(where: {
            $0.uuidString.caseInsensitiveCompare(profile) == .orderedSame
        }) {
            let safe = favorites.filter { isShareable($0.url) }
            values["favorites:order:\(profile)"] = BrowserSyncMerge.text(safe.map { $0.id.uuidString })
            for favorite in safe {
                let item = SyncedFavorite(id: favorite.id, url: favorite.url, title: favorite.title,
                                          customName: favorite.customName)
                values["favorite:\(profile):\(favorite.id.uuidString)"] = BrowserSyncMerge.text(item)
            }
        }

        if let settings = snapshot.settings {
            encode(settings.searchEngine, key: "setting:searchEngine", into: &values)
            encode(settings.remoteSuggestions, key: "setting:remoteSuggestions", into: &values)
            encode(settings.archiveAfterHours, key: "setting:archiveAfterHours", into: &values)
            encode(settings.blockContent, key: "setting:blockContent", into: &values)
            encode(settings.externalLinksSpaceID, key: "setting:externalLinksSpaceID", into: &values)
            encode(settings.linkRoutingEnabled, key: "setting:linkRoutingEnabled", into: &values)
            encode(settings.linkRoutingRules, key: "setting:linkRoutingRules", into: &values)
            encode(settings.desktopSitesWhenUnfolded, key: "setting:desktopSitesWhenUnfolded", into: &values)
            encode(settings.declineCookieBanners, key: "setting:declineCookieBanners", into: &values)
            encode(settings.cleanLinks, key: "setting:cleanLinks", into: &values)
            encode(settings.siteDesktopOverrides, key: "setting:siteDesktopOverrides", into: &values)
            encode(settings.filterGroups.map(\.rawValue).sorted(), key: "setting:filterGroups", into: &values)
            encode(settings.blockingDisabledHosts.sorted(), key: "setting:blockingDisabledHosts", into: &values)

            let profiles = settings.websiteProfiles.filter { !localOnlyProfileIDs.contains($0.id) }
            values["websiteProfiles:order"] = BrowserSyncMerge.text(profiles.map { $0.id.uuidString })
            for profile in profiles {
                let item = SyncedProfile(id: profile.id, name: profile.name)
                values["websiteProfile:\(profile.id.uuidString)"] = BrowserSyncMerge.text(item)
            }
        }

        return values.compactMapValues { $0 }
    }

    /// A per-device index of open web pages. This never enters the shared snapshot
    /// projection, so consumers can inspect it without replacing local Today tabs.
    public static func deviceTabsValue(from snapshot: BrowserSnapshot, deviceID: UUID,
                                       deviceName: String, sharing: Bool, updatedAt: Date) -> String? {
        let spaces = sharing ? snapshot.spaces.filter { !$0.isSyncLocalOnly }.compactMap { space -> DeviceSpace? in
            let tabs = space.today.filter { !$0.isPinned && isShareable($0.url) }.prefix(500).compactMap { tab -> DeviceTab? in
                guard let url = tab.url.flatMap(safeWebURL) else { return nil }
                let title = String((tab.customTitle ?? tab.title).prefix(512))
                return DeviceTab(id: tab.id, title: title.isEmpty ? (url.host ?? url.absoluteString) : title, url: url)
            }
            guard !tabs.isEmpty else { return nil }
            return DeviceSpace(id: space.id, name: String(space.name.prefix(128)), tabs: tabs)
        } : []
        return BrowserSyncMerge.text(DeviceTabs(deviceID: deviceID, deviceName: String(deviceName.prefix(128)),
                                                sharing: sharing, updatedAt: updatedAt, spaces: spaces))
    }

    public static func otherDevices(in values: [String: String], excluding deviceID: UUID,
                                    now: Date = .now) -> [BrowserSyncRemoteDevice] {
        let freshnessLimit: TimeInterval = 30 * 24 * 60 * 60
        return values.compactMap { key, value -> BrowserSyncRemoteDevice? in
            guard key.hasPrefix("deviceTabs:"), let record = BrowserSyncMerge.value(DeviceTabs.self, from: value),
                  record.deviceID != deviceID, record.sharing,
                  now.timeIntervalSince(record.updatedAt) <= freshnessLimit,
                  record.updatedAt <= now.addingTimeInterval(5 * 60) else { return nil }
            let spaces = record.spaces.compactMap { space -> BrowserSyncRemoteSpace? in
                let tabs = space.tabs.compactMap { tab -> BrowserSyncRemoteTab? in
                    guard let url = safeWebURL(tab.url) else { return nil }
                    return BrowserSyncRemoteTab(id: tab.id, title: tab.title, url: url)
                }
                return tabs.isEmpty ? nil : BrowserSyncRemoteSpace(id: space.id, name: space.name, tabs: tabs)
            }
            guard !spaces.isEmpty else { return nil }
            return BrowserSyncRemoteDevice(id: record.deviceID, name: record.deviceName,
                                           updatedAt: record.updatedAt, spaces: spaces)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Applies merged values while preserving local-only state such as Today
    /// tabs, selected tabs, split layouts, sidebar posture, history, and
    /// permission grants. A completely empty/corrupt sync view never clears
    /// the local browser state.
    public static func applying(_ values: [String: String], to snapshot: BrowserSnapshot) -> BrowserSnapshot {
        let syncedSpaces = decodeItems(SyncedSpace.self, values: values, prefix: "space:")
        guard !syncedSpaces.isEmpty else { return snapshot }

        let localSpaces = Dictionary(uniqueKeysWithValues: snapshot.spaces.map { ($0.id, $0) })
        let order = (decodeStrings(values["spaces:order"]) ?? []).compactMap(UUID.init(uuidString:))
        let orderedSpaceIDs = ordered(Set(syncedSpaces.keys), by: order, fallback: snapshot.spaces.map(\.id))
        var spaces = orderedSpaceIDs.compactMap { id -> SpaceRecord? in
            guard let metadata = syncedSpaces[id] else { return nil }
            let local = localSpaces[id]
            let pinPrefix = "pin:\(id.uuidString):"
            let pinsByID = decodeItems(SyncedPin.self, values: values, prefix: pinPrefix)
            let pinOrder = (decodeStrings(values["pins:order:\(id.uuidString)"]) ?? []).compactMap(UUID.init(uuidString:))
            let localOnlyPins = (local?.pinned ?? []).filter { !isShareable($0.url) }
            let sharedPins = ordered(Set(pinsByID.keys), by: pinOrder, fallback: local?.pinned.map(\.id) ?? [])
                .compactMap { pinID -> TabRecord? in
                    guard let pin = pinsByID[pinID], isShareable(pin.url) else { return nil }
                    let previous = local?.pinned.first { $0.id == pinID }
                    let samePage = previous?.url == pin.url
                    return TabRecord(id: pin.id, url: pin.url, title: pin.title, isPinned: true,
                                     lastActive: previous?.lastActive ?? .distantPast,
                                     interactionState: samePage ? previous?.interactionState : nil,
                                     favoriteID: pin.favoriteID,
                                     pinnedHomeURL: pin.homeURL ?? previous?.pinnedHomeURL,
                                     windowKey: nil, customTitle: pin.customTitle, pinFolderID: pin.folderID,
                                     websiteSessionProfileID: pin.websiteProfileID)
                }
            let pins = sharedPins + localOnlyPins

            let folderPrefix = "folder:\(id.uuidString):"
            let foldersByID = decodeItems(SyncedFolder.self, values: values, prefix: folderPrefix)
            let folderOrder = (decodeStrings(values["folders:order:\(id.uuidString)"]) ?? []).compactMap(UUID.init(uuidString:))
            let folders = ordered(Set(foldersByID.keys), by: folderOrder, fallback: local?.pinFolders?.map(\.id) ?? [])
                .compactMap { folderID -> PinFolder? in
                    guard let folder = foldersByID[folderID] else { return nil }
                    let previous = local?.pinFolders?.first { $0.id == folderID }
                    var restored = PinFolder(id: folder.id, name: folder.name, parentID: folder.parentID,
                                             isCollapsed: previous?.isCollapsed ?? false)
                    if let source = folder.feedSource.flatMap(safeWebURL) {
                        let title = folder.feedTitle ?? folder.name
                        restored.feed = LiveFolderFeed(source: source, title: title, articles: [])
                        restored.feedNeedsActivation = previous?.feed == nil || previous?.feedNeedsActivation == true
                    }
                    return restored
                }

            let localToday = local?.today ?? []
            let localSelected = local?.selectedTabID
            let selected = localSelected.flatMap { selectedID in
                pins.contains(where: { $0.id == selectedID }) || localToday.contains(where: { $0.id == selectedID })
                    ? selectedID : nil
            }
            return SpaceRecord(id: id, name: metadata.name, symbol: metadata.symbol, colorIndex: metadata.colorIndex,
                               pinned: pins, today: localToday, selectedTabID: selected,
                               isSidebarOpen: local?.isSidebarOpen ?? true, themeHue: metadata.themeHue,
                               themeShade: metadata.themeShade, appearance: metadata.appearance,
                               pinFolders: folders.isEmpty ? nil : folders, splitPair: local?.splitPair,
                               websiteProfileID: metadata.websiteProfileID)
        }
        let sharedSpaceIDs = Set(syncedSpaces.keys)
        let localOnlySpaces = snapshot.spaces.filter { space in
            !space.today.isEmpty && !sharedSpaceIDs.contains(space.id)
        }.map { source -> SpaceRecord in
            var local = source
            local.isSyncLocalOnly = true
            local.pinned = []
            local.pinFolders = nil
            local.today = local.today.map { tab in
                var tab = tab
                tab.isPinned = false
                tab.pinnedHomeURL = nil
                tab.favoriteID = nil
                tab.pinFolderID = nil
                return tab
            }
            let todayIDs = Set(local.today.map(\.id))
            if let selected = local.selectedTabID, !todayIDs.contains(selected) {
                local.selectedTabID = local.today.first?.id
            }
            if let split = local.splitPair, split.tabs.contains(where: { !todayIDs.contains($0) }) {
                local.splitPair = nil
            }
            return local
        }
        spaces.append(contentsOf: localOnlySpaces)
        guard !spaces.isEmpty else { return snapshot }

        var favorites = snapshot.profileFavorites ?? [FavoriteProfileKey.default: snapshot.favorites]
        let favoriteOrders = values.keys.filter { $0.hasPrefix("favorites:order:") }
        for orderKey in favoriteOrders {
            let profile = String(orderKey.dropFirst("favorites:order:".count))
            guard isValidProfileKey(profile) else { continue }
            let prefix = "favorite:\(profile):"
            let byID = decodeItems(SyncedFavorite.self, values: values, prefix: prefix)
                .filter { safeWebURL($0.value.url) != nil }
            let order = (decodeStrings(values[orderKey]) ?? []).compactMap(UUID.init(uuidString:))
            let shared = ordered(Set(byID.keys), by: order, fallback: favorites[profile, default: []].map(\.id))
                .compactMap { id -> Favorite? in
                    guard let item = byID[id] else { return nil }
                    return Favorite(id: item.id, url: item.url, title: item.title,
                                    customName: item.customName, order: 0)
                }
            let localOnly = favorites[profile, default: []].filter { !isShareable($0.url) }
            favorites[profile] = (shared + localOnly).enumerated().map { index, favorite in
                var favorite = favorite
                favorite.order = index
                return favorite
            }
        }
        for key in values.keys where key.hasPrefix("favorite:") {
            let remainder = key.dropFirst("favorite:".count)
            guard let separator = remainder.firstIndex(of: ":") else { continue }
            let profile = String(remainder[..<separator])
            if favorites[profile] == nil, isValidProfileKey(profile) { favorites[profile] = [] }
        }

        let retainedProfiles = Set(localOnlySpaces.compactMap(\.websiteProfileID))
        let settings = applyingSettings(values, to: snapshot.settings, retainingProfiles: retainedProfiles)
        let selectedSpace = snapshot.selectedSpaceID.flatMap { id in spaces.contains(where: { $0.id == id }) ? id : nil }
        let legacyFavorites = favorites[FavoriteProfileKey.default] ?? []
        return BrowserSnapshot(spaces: spaces, selectedSpaceID: selectedSpace, favorites: legacyFavorites,
                               archive: snapshot.archive, settings: settings, saved: snapshot.saved,
                               profileFavorites: favorites)
    }

    /// True only for known keys with a decodable payload. Merge code uses this
    /// to retain unknown or newer-client fields rather than mistaking them for
    /// local deletions.
    public static func understands(key: String, value: String) -> Bool {
        if key == "spaces:order" || key.hasPrefix("pins:order:") || key.hasPrefix("folders:order:")
            || key.hasPrefix("favorites:order:") || key == "websiteProfiles:order" {
            return decodeStrings(value) != nil
        }
        if key.hasPrefix("space:") { return BrowserSyncMerge.value(SyncedSpace.self, from: value) != nil }
        if key.hasPrefix("pin:") {
            guard let pin = BrowserSyncMerge.value(SyncedPin.self, from: value) else { return false }
            return isShareable(pin.url)
        }
        if key.hasPrefix("folder:") { return BrowserSyncMerge.value(SyncedFolder.self, from: value) != nil }
        if key.hasPrefix("favorite:") {
            guard let favorite = BrowserSyncMerge.value(SyncedFavorite.self, from: value) else { return false }
            return isShareable(favorite.url)
        }
        if key.hasPrefix("websiteProfile:") { return BrowserSyncMerge.value(SyncedProfile.self, from: value) != nil }
        if key.hasPrefix("deviceTabs:") {
            guard let record = BrowserSyncMerge.value(DeviceTabs.self, from: value),
                  key == "deviceTabs:\(record.deviceID.uuidString.lowercased())" else { return false }
            return record.spaces.allSatisfy { space in space.tabs.allSatisfy { isShareable($0.url) } }
        }
        switch key {
        case "setting:searchEngine": return BrowserSyncMerge.value(SearchEngine.self, from: value) != nil
        case "setting:remoteSuggestions", "setting:blockContent", "setting:linkRoutingEnabled",
             "setting:desktopSitesWhenUnfolded", "setting:declineCookieBanners", "setting:cleanLinks":
            return BrowserSyncMerge.value(Bool.self, from: value) != nil
        case "setting:archiveAfterHours": return BrowserSyncMerge.value(Double.self, from: value) != nil
        case "setting:externalLinksSpaceID": return value == "null" || BrowserSyncMerge.value(UUID.self, from: value) != nil
        case "setting:linkRoutingRules": return BrowserSyncMerge.value([RouteRule].self, from: value) != nil
        case "setting:siteDesktopOverrides": return BrowserSyncMerge.value([String: Bool].self, from: value) != nil
        case "setting:filterGroups": return BrowserSyncMerge.value([String].self, from: value) != nil
        case "setting:blockingDisabledHosts": return BrowserSyncMerge.value([String].self, from: value) != nil
        default: return false
        }
    }

    private static func applyingSettings(_ values: [String: String], to existing: BrowserSettings?,
                                         retainingProfiles: Set<UUID>) -> BrowserSettings? {
        let knownSettingKeys = values.keys.filter { $0.hasPrefix("setting:") || $0.hasPrefix("websiteProfile:") || $0 == "websiteProfiles:order" }
        guard !knownSettingKeys.isEmpty else { return existing }
        var settings = existing ?? BrowserSettings()
        apply(SearchEngine.self, key: "setting:searchEngine", values: values) { settings.searchEngine = $0 }
        apply(Bool.self, key: "setting:remoteSuggestions", values: values) { settings.remoteSuggestions = $0 }
        apply(Double.self, key: "setting:archiveAfterHours", values: values) { settings.archiveAfterHours = $0 }
        apply(Bool.self, key: "setting:blockContent", values: values) { settings.blockContent = $0 }
        apply(UUID?.self, key: "setting:externalLinksSpaceID", values: values) { settings.externalLinksSpaceID = $0 }
        apply(Bool.self, key: "setting:linkRoutingEnabled", values: values) { settings.linkRoutingEnabled = $0 }
        apply([RouteRule].self, key: "setting:linkRoutingRules", values: values) { settings.linkRoutingRules = $0 }
        apply(Bool.self, key: "setting:desktopSitesWhenUnfolded", values: values) { settings.desktopSitesWhenUnfolded = $0 }
        apply(Bool.self, key: "setting:declineCookieBanners", values: values) { settings.declineCookieBanners = $0 }
        apply(Bool.self, key: "setting:cleanLinks", values: values) { settings.cleanLinks = $0 }
        apply([String: Bool].self, key: "setting:siteDesktopOverrides", values: values) { settings.siteDesktopOverrides = $0 }
        apply([String].self, key: "setting:filterGroups", values: values) { raw in
            settings.filterGroups = Set(raw.compactMap(FilterGroup.init(rawValue:)))
        }
        apply([String].self, key: "setting:blockingDisabledHosts", values: values) { settings.blockingDisabledHosts = Set($0) }

        let profilesByID = decodeItems(SyncedProfile.self, values: values, prefix: "websiteProfile:")
        if values["websiteProfiles:order"] != nil {
            let order = (decodeStrings(values["websiteProfiles:order"]) ?? []).compactMap(UUID.init(uuidString:))
            let profiles: [WebsiteProfile] = ordered(Set(profilesByID.keys), by: order,
                                                     fallback: settings.websiteProfiles.map(\.id))
                .compactMap { id -> WebsiteProfile? in
                    guard let value = profilesByID[id] else { return nil }
                    return WebsiteProfile(id: value.id, name: value.name)
                }
            let retained = existing?.websiteProfiles.filter { retainingProfiles.contains($0.id) } ?? []
            let currentIDs = Set(profiles.map(\.id))
            settings.websiteProfiles = profiles + retained.filter { !currentIDs.contains($0.id) }
        }
        return settings
    }

    private static func apply<T: Decodable>(_ type: T.Type, key: String, values: [String: String],
                                            update: (T) -> Void) {
        guard let text = values[key], let value = BrowserSyncMerge.value(type, from: text) else { return }
        update(value)
    }

    private static func encode<T: Encodable>(_ value: T, key: String, into values: inout [String: String]) {
        values[key] = BrowserSyncMerge.text(value)
    }

    private static func decodeItems<T: Decodable>(_ type: T.Type, values: [String: String],
                                                  prefix: String) -> [UUID: T] {
        var result: [UUID: T] = [:]
        for (key, value) in values where key.hasPrefix(prefix) {
            let suffix = key.dropFirst(prefix.count)
            guard let idText = suffix.split(separator: ":").last,
                  let id = UUID(uuidString: String(idText)), let item = BrowserSyncMerge.value(type, from: value) else { continue }
            result[id] = item
        }
        return result
    }

    private static func decodeStrings(_ text: String?) -> [String]? {
        guard let text else { return nil }
        return BrowserSyncMerge.value([String].self, from: text)
    }

    private static func ordered(_ ids: Set<UUID>, by order: [UUID], fallback: [UUID]) -> [UUID] {
        var result: [UUID] = []
        var seen: Set<UUID> = []
        for id in order + fallback where ids.contains(id) && seen.insert(id).inserted { result.append(id) }
        return result + ids.subtracting(seen).sorted { $0.uuidString < $1.uuidString }
    }

    private static func isValidProfileKey(_ key: String) -> Bool {
        key == FavoriteProfileKey.default || UUID(uuidString: key) != nil
    }

    private static func isShareable(_ url: URL?) -> Bool {
        guard let url else { return false }
        return safeWebURL(url) != nil
    }

    private static func safeWebURL(_ url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else { return nil }
        return url
    }
}
