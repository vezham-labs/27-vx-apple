import Foundation
import Suggest
import Testing
@testable import BrowserCore

@Test func syncProjectionSharesPinnedStateButLeavesTransientAndSensitiveStateLocal() {
    let spaceID = UUID()
    let pinID = UUID()
    let privateURL = URL(string: "https://user:secret@example.com/private")!
    let safeURL = URL(string: "https://example.com/pinned")!
    let pinned = tab(id: pinID, url: safeURL, title: "Pinned", isPinned: true,
                     interactionState: Data("local webkit state".utf8))
    let today = tab(id: UUID(), url: URL(string: "https://example.com/today"), title: "Today",
                    isPinned: false, interactionState: Data("today state".utf8))
    let space = spaceRecord(id: spaceID, pinned: [pinned], today: [today])
    let favorite = Favorite(url: privateURL, title: "Credentialed", order: 0)
    var settings = BrowserSettings()
    settings.sitePermissions = ["camera.example": ["camera": true]]
    let snapshot = BrowserSnapshot(spaces: [space], selectedSpaceID: spaceID, favorites: [favorite],
                                   archive: [], settings: settings, saved: nil)

    let values = BrowserSyncItems.values(from: snapshot)

    #expect(values["pin:\(spaceID.uuidString):\(pinID.uuidString)"] != nil)
    #expect(!values.keys.contains { $0.hasPrefix("tab:") })
    #expect(!values.keys.contains { $0.hasPrefix("favorite:") })
    #expect(!values.keys.contains { $0.contains("interactionState") })
    #expect(!values.keys.contains { $0.contains("sitePermissions") })
}

@Test func syncApplicationPreservesLocalTodayTabsAndPinInteractionState() throws {
    let spaceID = UUID()
    let pinID = UUID()
    let todayID = UUID()
    let url = URL(string: "https://example.com/pinned")!
    let localPin = tab(id: pinID, url: url, title: "Old title", isPinned: true,
                       interactionState: Data("local webkit state".utf8))
    let credentialedPinID = UUID()
    let credentialedPin = tab(id: credentialedPinID,
                              url: URL(string: "https://user:secret@example.com/local-only")!,
                              title: "Local-only pin", isPinned: true)
    let localToday = tab(id: todayID, url: URL(string: "https://local.example/"), title: "Local Today",
                         isPinned: false, interactionState: Data("today state".utf8))
    let local = BrowserSnapshot(spaces: [spaceRecord(id: spaceID, name: "Old", pinned: [localPin, credentialedPin],
                                                       today: [localToday], selectedTabID: todayID,
                                                       isSidebarOpen: false)],
                                selectedSpaceID: spaceID, favorites: [], archive: [], settings: BrowserSettings(), saved: nil)
    var remoteSettings = BrowserSettings()
    remoteSettings.automaticPiPDisabledHosts = ["video.example.com"]
    let remote = BrowserSnapshot(spaces: [spaceRecord(id: spaceID, name: "Renamed", symbol: "briefcase.fill",
                                                        pinned: [tab(id: pinID, url: url, title: "Updated title", isPinned: true)],
                                                        today: [])],
                                 selectedSpaceID: nil, favorites: [], archive: [], settings: remoteSettings, saved: nil)

    let projected = BrowserSyncItems.values(from: remote)
    let restored = BrowserSyncItems.applying(projected, to: local)
    let result = try #require(restored.spaces.first)
    let pin = try #require(result.pinned.first)
    let today = try #require(result.today.first)
    let preservedCredentialedPin = try #require(result.pinned.first { $0.id == credentialedPinID })

    #expect(result.name == "Renamed")
    #expect(restored.settings?.automaticPiPDisabledHosts == ["video.example.com"])
    #expect(result.symbol == "briefcase.fill")
    #expect(result.isSidebarOpen == false)
    #expect(result.selectedTabID == todayID)
    #expect(pin.title == "Updated title")
    #expect(pin.interactionState == Data("local webkit state".utf8))
    #expect(preservedCredentialedPin.url == credentialedPin.url)
    #expect(today.id == todayID)
    #expect(today.interactionState == Data("today state".utf8))
}

@Test func syncProfilesAndFavoritesKeepTheirStableIDsAndScopes() throws {
    let profileID = UUID()
    let favoriteID = UUID()
    let websiteProfile = try #require(WebsiteProfile(id: profileID, name: "Work"))
    let favorite = Favorite(id: favoriteID, url: URL(string: "https://example.com")!, title: "Example", order: 2)
    var settings = BrowserSettings()
    settings.websiteProfiles = [websiteProfile]
    let source = BrowserSnapshot(spaces: [spaceRecord(id: UUID())], selectedSpaceID: nil, favorites: [], archive: [],
                                 settings: settings, saved: nil,
                                 profileFavorites: [FavoriteProfileKey.default: [], profileID.uuidString: [favorite]])

    let restored = BrowserSyncItems.applying(BrowserSyncItems.values(from: source), to: source)
    let restoredProfile = try #require(restored.settings?.websiteProfiles.first)
    let restoredFavorite = try #require(restored.profileFavorites?[profileID.uuidString]?.first)

    #expect(restoredProfile.id == profileID)
    #expect(restoredProfile.name == "Work")
    #expect(restoredFavorite.id == favoriteID)
    #expect(restoredFavorite.order == 0)
}

@Test func syncApplicationRejectsInvalidSpacePayloadWithoutClearingLocalSnapshot() {
    let original = BrowserSnapshot(spaces: [spaceRecord(id: UUID())], selectedSpaceID: nil, favorites: [],
                                   archive: [], settings: nil, saved: nil)
    let result = BrowserSyncItems.applying(["space:not-a-uuid": "bad"], to: original)
    #expect(result.spaces.count == 1)
    #expect(result.spaces[0].id == original.spaces[0].id)
}

@Test func syncGitHubFolderKeepsAccountDataOnlyForSameProfile() throws {
    let spaceID = UUID()
    let profileID = UUID()
    var folder = PinFolder(name: "Pull Requests")
    folder.feed = LiveFolderFeed(source: try #require(URL(string: "https://github.com/_ark/live-pull-requests")),
                                 title: folder.name, articles: [
        .init(title: "Private review", url: try #require(URL(string: "https://github.com/acme/app/pull/1")))
    ])
    folder.knownGitHubOwners = ["acme"]
    folder.hiddenGitHubOwners = ["acme"]
    var space = spaceRecord(id: spaceID)
    space.websiteProfileID = profileID
    space.pinFolders = [folder]
    let local = BrowserSnapshot(spaces: [space], selectedSpaceID: spaceID, favorites: [], archive: [],
                                settings: nil, saved: nil)
    let values = BrowserSyncItems.values(from: local)
    #expect(!values.values.contains { $0.contains("Private review") || $0.contains("acme") })

    let same = BrowserSyncItems.applying(values, to: local)
    let retained = try #require(same.spaces.first?.pinFolders?.first)
    #expect(retained.feed?.articles.count == 1)
    #expect(retained.hiddenGitHubOwners == ["acme"])
    #expect(retained.feedNeedsActivation != true)

    space.websiteProfileID = UUID()
    let remote = BrowserSnapshot(spaces: [space], selectedSpaceID: spaceID, favorites: [], archive: [],
                                 settings: nil, saved: nil)
    let changed = BrowserSyncItems.applying(BrowserSyncItems.values(from: remote), to: local)
    let cleared = try #require(changed.spaces.first?.pinFolders?.first)
    #expect(cleared.feed?.articles.isEmpty == true)
    #expect(cleared.knownGitHubOwners == nil)
    #expect(cleared.hiddenGitHubOwners == nil)
    #expect(cleared.feedNeedsActivation == true)
}

@Test func syncApplicationRejectsCredentialedFavoriteFromSharedFolder() throws {
    let spaceID = UUID()
    let favorite = Favorite(url: URL(string: "https://user:secret@example.com/private")!, title: "Private URL", order: 0)
    let original = BrowserSnapshot(spaces: [spaceRecord(id: spaceID)], selectedSpaceID: spaceID, favorites: [],
                                   archive: [], settings: nil, saved: nil)
    var values = BrowserSyncItems.values(from: original)
    values["favorites:order:\(FavoriteProfileKey.default)"] = try syncText([favorite.id.uuidString])
    values["favorite:\(FavoriteProfileKey.default):\(favorite.id.uuidString)"] = try syncText(favorite)

    let restored = BrowserSyncItems.applying(values, to: original)

    #expect(restored.favorites.isEmpty)
}

@Test func deletedSharedSpaceRetainsItsTodayTabsAsDeviceLocal() throws {
    let removedSpaceID = UUID()
    let survivingSpaceID = UUID()
    let profileID = UUID()
    let today = tab(id: UUID(), url: URL(string: "https://local.example/"), title: "Keep me", isPinned: false)
    var removedSpace = spaceRecord(id: removedSpaceID, name: "Research", today: [today], selectedTabID: today.id)
    removedSpace.websiteProfileID = profileID
    var localSettings = BrowserSettings()
    localSettings.websiteProfiles = [try #require(WebsiteProfile(id: profileID, name: "Research"))]
    let local = BrowserSnapshot(spaces: [removedSpace, spaceRecord(id: survivingSpaceID)],
                                selectedSpaceID: removedSpaceID, favorites: [], archive: [],
                                settings: localSettings, saved: nil)
    let remote = BrowserSnapshot(spaces: [spaceRecord(id: survivingSpaceID)], selectedSpaceID: survivingSpaceID,
                                 favorites: [], archive: [], settings: BrowserSettings(), saved: nil)

    let restored = BrowserSyncItems.applying(BrowserSyncItems.values(from: remote), to: local)
    let localOnly = try #require(restored.spaces.first { $0.id == removedSpaceID })
    let restoredTab = try #require(localOnly.today.first)

    #expect(localOnly.isSyncLocalOnly)
    #expect(localOnly.pinned.isEmpty)
    #expect(restoredTab.id == today.id)
    #expect(restoredTab.url == today.url)
    #expect(restored.settings?.websiteProfiles.contains { $0.id == profileID } == true)
    #expect(BrowserSyncItems.values(from: restored)["space:\(removedSpaceID.uuidString)"] == nil)
}

@Test func olderSpaceRecordDefaultsSyncLocalOnlyToFalse() throws {
    let id = UUID()
    let older = """
    {"id":"\(id.uuidString)","name":"Personal","symbol":"house.fill","colorIndex":0,"pinned":[],"today":[],"isSidebarOpen":true}
    """
    let decoded = try JSONDecoder().decode(SpaceRecord.self, from: Data(older.utf8))
    #expect(!decoded.isSyncLocalOnly)
    let roundTrip = try JSONDecoder().decode(SpaceRecord.self, from: JSONEncoder().encode(decoded))
    #expect(!roundTrip.isSyncLocalOnly)
}

private func tab(id: UUID, url: URL?, title: String, isPinned: Bool,
                 interactionState: Data? = nil) -> TabRecord {
    TabRecord(id: id, url: url, title: title, isPinned: isPinned, lastActive: .distantPast,
              interactionState: interactionState)
}

private func spaceRecord(id: UUID, name: String = "Personal", symbol: String = "house.fill", colorIndex: Int = 0,
                         pinned: [TabRecord] = [], today: [TabRecord] = [], selectedTabID: UUID? = nil,
                         isSidebarOpen: Bool = true) -> SpaceRecord {
    SpaceRecord(id: id, name: name, symbol: symbol, colorIndex: colorIndex, pinned: pinned, today: today,
                selectedTabID: selectedTabID, isSidebarOpen: isSidebarOpen)
}

private func syncText<T: Encodable>(_ value: T) throws -> String {
    guard let text = BrowserSyncMerge.text(value) else { throw SyncTestError.encodingFailed }
    return text
}

private enum SyncTestError: Error { case encodingFailed }

