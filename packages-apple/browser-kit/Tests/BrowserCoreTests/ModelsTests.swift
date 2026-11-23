import Foundation
import Testing
@testable import BrowserCore
import Suggest

@Test @MainActor func recentTabsPreferTheSelectionAndLimitResults() {
    let pinned = BrowserTab(url: nil, title: "Pinned", isPinned: true, lastActive: Date(timeIntervalSince1970: 30))
    let selected = BrowserTab(url: nil, title: "Selected", lastActive: Date(timeIntervalSince1970: 10))
    let newest = BrowserTab(url: nil, title: "Newest", lastActive: Date(timeIntervalSince1970: 40))
    let space = Space(name: "Work", pinned: [pinned], today: [selected, newest], selectedTabID: selected.id)
    #expect(space.recentTabs(limit: 2).map(\.title) == ["Selected", "Newest"])
    #expect(space.recentTabs(limit: 0).isEmpty)
    space.selectedTabID = nil
    #expect(space.recentTabs(limit: 3).map(\.title) == ["Newest", "Pinned", "Selected"])
}

@Test @MainActor func splitPairFollowsSelectionAndSurvivesASnapshot() throws {
    let first = BrowserTab(url: URL(string: "https://example.com/first"))
    let second = BrowserTab(url: URL(string: "https://example.com/second"), isPinned: true)
    let favorite = BrowserTab(url: URL(string: "https://example.com/favorite"))
    favorite.favoriteID = UUID()
    let other = BrowserTab(url: URL(string: "https://example.com/other"))
    let space = Space(name: "Work", pinned: [second], today: [first, favorite, other], selectedTabID: first.id)

    #expect(!space.splitWith(favorite))
    #expect(space.splitWith(second))
    space.resizeSplit(to: 2)
    #expect(space.splitPair?.fraction == 0.75)
    space.resizeSplit(to: .infinity)
    #expect(space.splitPair?.fraction == 0.75)
    space.selectedTabID = other.id
    #expect(space.activeSplitTabs == nil)
    space.selectedTabID = second.id
    #expect(space.activeSplitTabs?.0 === first)

    let snapshot = try JSONEncoder().encode(space.record)
    let restored = Space(try JSONDecoder().decode(SpaceRecord.self, from: snapshot))
    #expect(restored.splitPair == space.splitPair)
    #expect(restored.activeSplitTabs?.1.id == second.id)
    #expect(restored.selectedTabID == second.id)
    var incomplete = restored.record
    incomplete.pinned.removeAll { $0.id == second.id }
    #expect(Space(incomplete).splitPair == nil)
    restored.separateTabs()
    #expect(restored.activeSplitTabs == nil)
    #expect(restored.selectedTabID == second.id)
}

@Suite struct LoadErrorTests {
    func err(_ code: Int, _ domain: String = NSURLErrorDomain) -> NSError { NSError(domain: domain, code: code) }

    @Test func classifiesCommonFailures() {
        #expect(LoadError(url: nil, error: err(NSURLErrorNotConnectedToInternet)).kind == .offline)
        #expect(LoadError(url: nil, error: err(NSURLErrorCannotFindHost)).kind == .notFound)
        #expect(LoadError(url: nil, error: err(NSURLErrorTimedOut)).kind == .timedOut)
        let cert = LoadError(url: nil, error: err(NSURLErrorServerCertificateUntrusted))
        #expect(cert.kind == .insecure)
        #expect(!cert.canRetry)
    }

    @Test func cancellationsAndDownloadsAreNotErrors() {
        #expect(LoadError.isIgnorable(err(NSURLErrorCancelled)))
        #expect(LoadError.isIgnorable(err(102, "WebKitErrorDomain")))
        #expect(!LoadError.isIgnorable(err(NSURLErrorTimedOut)))
    }
}

@Suite struct SettingsCodingTests {
    @Test func olderSettingsStillLoad() throws {
        let old = #"{"searchEngine":{"duckDuckGo":{}},"remoteSuggestions":false,"archiveAfterHours":24,"blockContent":true}"#
        let s = try JSONDecoder().decode(BrowserSettings.self, from: Data(old.utf8))
        #expect(s.searchEngine == .duckDuckGo)
        #expect(s.remoteSuggestions == false)
        #expect(s.desktopSitesWhenUnfolded)
        #expect(s.sitePermissions.isEmpty)
        #expect(s.websiteProfiles.isEmpty)
        #expect(s.unloadIdlePagesAfterMinutes == 30)
    }

    @Test func roundTrips() throws {
        var s = BrowserSettings()
        s.siteDesktopOverrides["example.com"] = false
        s.sitePermissions["meet.google.com"] = ["camera": true]
        s.unloadIdlePagesAfterMinutes = 10
        let back = try JSONDecoder().decode(BrowserSettings.self, from: JSONEncoder().encode(s))
        #expect(back == s)
    }

    @Test @MainActor func websiteProfileMetadataSurvivesSnapshot() throws {
        let profile = try #require(WebsiteProfile(name: "  Research  "))
        #expect(profile.name == "Research")
        #expect(WebsiteProfile(name: "  ") == nil)
        var settings = BrowserSettings()
        settings.websiteProfiles = [profile]
        let tab = BrowserTab(url: nil)
        tab.websiteSessionProfileID = profile.id
        let space = Space(name: "Work", today: [tab])
        space.websiteProfileID = profile.id
        let snapshot = BrowserSnapshot(spaces: [space.record], selectedSpaceID: space.id,
                                       favorites: [], archive: [], settings: settings, saved: [])
        let restored = try JSONDecoder().decode(BrowserSnapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(restored.settings?.websiteProfiles == [profile])
        let record = try #require(restored.spaces.first)
        #expect(Space(record).websiteProfileID == profile.id)
        #expect(Space(record).today.first?.websiteSessionProfileID == profile.id)
    }
}

@Suite struct ThumbnailStoreTests {
    @Test func keepsWantedPicturesAndDeletesTheRest() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ThumbnailStore(directory: dir)
        let kept = UUID(), gone = UUID(), removed = UUID()
        store.save(Data([1]), for: kept)
        store.save(Data([2]), for: gone)
        store.save(Data([3]), for: removed)
        store.remove(removed)

        #expect(store.loadAll(keeping: [kept, removed]) == [kept: Data([1])])
        #expect(store.loadAll(keeping: [kept, gone]) == [kept: Data([1])])
    }
}

@Suite struct SnapshotCodingTests {
    @Test func stateFromBeforeSavedSitesStillLoads() throws {
        let old = #"{"spaces":[],"favorites":[],"archive":[]}"#
        let snap = try JSONDecoder().decode(BrowserSnapshot.self, from: Data(old.utf8))
        #expect(snap.saved == nil)
        #expect(snap.profileFavorites == nil)
    }

    @Test func savedSitesRoundTrip() throws {
        let site = SavedSite(url: URL(string: "https://example.com/a")!, title: "A", savedAt: Date(timeIntervalSince1970: 1_000))
        let snap = BrowserSnapshot(spaces: [], selectedSpaceID: nil, favorites: [], archive: [], settings: nil, saved: [site])
        let back = try JSONDecoder().decode(BrowserSnapshot.self, from: JSONEncoder().encode(snap))
        #expect(back.saved == [site])
    }
    @Test func profileFavoritesRoundTripWithoutChangingLegacyDefaultField() throws {
        let defaultFavorite = Favorite(url: URL(string: "https://default.example")!, title: "Default", order: 0)
        let workID = UUID(uuidString: "A1111111-2222-4333-8444-555555555555")!
        let workFavorite = Favorite(url: URL(string: "https://work.example")!, title: "Work", order: 0)
        let profileFavorites = [FavoriteProfileKey.default: [defaultFavorite], workID.uuidString: [workFavorite]]
        let snap = BrowserSnapshot(spaces: [], selectedSpaceID: nil, favorites: [defaultFavorite], archive: [],
                                   settings: nil, saved: nil, profileFavorites: profileFavorites)
        let back = try JSONDecoder().decode(BrowserSnapshot.self, from: JSONEncoder().encode(snap))
        #expect(back.favorites == [defaultFavorite])
        #expect(back.profileFavorites == profileFavorites)
        #expect(FavoriteProfileKey.key(for: workID) == workID.uuidString)
    }
    @Test func tabsFromBeforeWindowKeysStillLoad() throws {
        let old = #"{"id":"6F1C2D4E-0000-4000-8000-000000000001","title":"A","isPinned":false,"lastActive":0}"#
        let record = try JSONDecoder().decode(TabRecord.self, from: Data(old.utf8))
        #expect(record.windowKey == nil)
    }

    @MainActor @Test func todayTabsKeepTheirWindowAndSharedTabsDont() throws {
        let window = UUID()
        let today = BrowserTab(url: URL(string: "https://example.com")!)
        today.windowKey = window
        let pinned = BrowserTab(url: URL(string: "https://example.org")!, isPinned: true)
        pinned.windowKey = window
        let decode = { (t: BrowserTab) in try JSONDecoder().decode(TabRecord.self, from: JSONEncoder().encode(t.record)) }
        #expect(BrowserTab(try decode(today)).windowKey == window)
        #expect(try decode(pinned).windowKey == nil)
    }
}
