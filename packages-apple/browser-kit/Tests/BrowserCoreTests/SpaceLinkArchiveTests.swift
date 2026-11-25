import CoreTransferable
import Foundation
import Testing
@testable import BrowserCore

@Suite struct SpaceLinkArchiveTests {
    @Test @MainActor func restoresVersionOneWithFreshTabIDsAndOriginalOrder() throws {
        let oldExport = """
            {"version":1,"name":"Work","pinned":[{"title":"Pinned","url":"https://example.com/pin"}],
             "today":[{"title":"First","url":"https://example.com/first"},{"title":"Second","url":"http://example.com/second"}]}
            """
        let archive = try SpaceLinkArchive(data: Data(oldExport.utf8))
        let windowKey = UUID()
        let space = archive.makeSpace(colorIndex: 2, windowKey: windowKey)

        #expect(space.name == "Work")
        #expect(space.pinned.map(\.title) == ["Pinned"])
        #expect(space.pinned.map(\.isPinned) == [true])
        #expect(space.today.map(\.title) == ["First", "Second"])
        #expect(space.today.allSatisfy { !$0.isPinned && $0.windowKey == windowKey })
        #expect(Set(space.allTabs.map(\.id)).count == 3)
        #expect(space.selectedTabID == nil)
        #expect(space.allTabs.allSatisfy { $0.interactionState == nil })
    }

    @Test @MainActor func roundTripDropsPrivateInternalAndCredentialedLinks() throws {
        let keep = BrowserTab(url: URL(string: "https://example.com/"), title: "Planning")
        let space = Space(name: "Work", today: [
            keep,
            BrowserTab(url: URL(string: "https://private.example/"), isPrivate: true),
            BrowserTab(url: URL(string: "ark://library")),
            BrowserTab(url: URL(string: "https://name:password@example.com/")),
        ])
        let export = try #require(SpaceLinkArchive(space: space))
        let restored = try SpaceLinkArchive(data: export.encoded()).makeSpace(colorIndex: 0)

        #expect(restored.today.map(\.url) == [keep.url])
        #expect(restored.today.first?.displayTitle == "Planning")
        #expect(restored.today.first?.id != keep.id)
        #expect(SpaceLinkArchive(space: Space(name: "Private", isPrivate: true)) == nil)
    }

    @Test @MainActor func roundTripPreservesPinnedHome() throws {
        let pin = BrowserTab(url: URL(string: "https://example.com/current"), title: "Pin", isPinned: true)
        pin.pinnedHomeURL = URL(string: "https://example.com/home")
        let archive = try #require(SpaceLinkArchive(space: Space(name: "Work", pinned: [pin])))
        let restored = try SpaceLinkArchive(data: archive.encoded()).makeSpace(colorIndex: 0)
        #expect(restored.pinned.first?.url == pin.url)
        #expect(restored.pinned.first?.pinnedHomeURL == pin.pinnedHomeURL)
        pin.pinnedHomeURL = URL(string: "https://user:secret@example.com/home")
        let sanitized = try #require(SpaceLinkArchive(space: Space(name: "Work", pinned: [pin])))
        let data = try sanitized.encoded()
        #expect(!String(decoding: data, as: UTF8.self).contains("secret"))
        #expect(try SpaceLinkArchive(data: data).makeSpace(colorIndex: 0).pinned.first?.pinnedHomeURL == nil)
    }

    @Test func validatesExternalFilesBeforeImporting() {
        func payload(version: Int = 1, url: String) -> Data {
            Data("""
                {"version":\(version),"name":"Work","pinned":[],"today":[{"title":"Link","url":"\(url)"}]}
                """.utf8)
        }
        #expect(throws: SpaceLinkArchive.InvalidArchive.unsupportedVersion) {
            try SpaceLinkArchive(data: payload(version: 2, url: "https://example.com/"))
        }
        for url in ["file:///tmp/local", "javascript:alert(1)", "https:///missing-host", "https://name:pass@example.com/"] {
            #expect(throws: SpaceLinkArchive.InvalidArchive.invalidLink) {
                try SpaceLinkArchive(data: payload(url: url))
            }
        }
        let unsafeHome = Data("""
            {"version":1,"name":"Work","pinned":[{"title":"Pin","url":"https://example.com/","pinnedHomeURL":"file:///tmp/local"}],"today":[]}
            """.utf8)
        #expect(throws: SpaceLinkArchive.InvalidArchive.invalidLink) {
            try SpaceLinkArchive(data: unsafeHome)
        }
        #expect(throws: SpaceLinkArchive.InvalidArchive.tooLarge) {
            try SpaceLinkArchive(data: Data(count: 2 * 1024 * 1024 + 1))
        }
    }

    @Test @MainActor func transfersSourceWithoutItsCacheAndPausesTheImportedFeed() async throws {
        let space = Space(name: "Research")
        let folder = try #require(space.addPinFolder(named: "Daily Notes"))
        let source = try #require(URL(string: "https://example.invalid/feed.xml"))
        let article = try #require(URL(string: "https://example.invalid/cached-article"))
        space.pinFolders[0].feed = LiveFolderFeed(source: source, title: "Notes", articles: [
            .init(title: "Private cache", url: article),
        ])
        let archive = try #require(SpaceLinkArchive(space: space))
        let data = try archive.encoded()
        #expect(!String(decoding: data, as: UTF8.self).contains("cached-article"))
        let restored = try SpaceLinkArchive(data: data).makeSpace(colorIndex: 0)
        let restoredFolder = try #require(restored.pinFolders.first)
        #expect(restoredFolder.id != folder.id)
        #expect(restoredFolder.name == folder.name)
        #expect(restoredFolder.feed?.source == source)
        #expect(restoredFolder.feed?.articles.isEmpty == true)
        #expect(restoredFolder.feedNeedsActivation == true)
        let snapshot = try JSONEncoder().encode(restored.record)
        let reloaded = Space(try JSONDecoder().decode(SpaceRecord.self, from: snapshot))
        #expect(reloaded.pinFolders.first?.feedNeedsActivation == true)
        #expect(try await reloaded.refreshLiveFolder(restoredFolder.id, allowActivation: false) == false)
    }

    @Test func rejectsAnUnsafeFeedSourceInASpaceFile() {
        let data = Data("""
            {
                "version":1,"name":"Research","pinned":[],"today":[],
                "pinFolders":[{"id":"30E5BDFA-EF4C-4EA8-B660-80AE69EDC351","name":"News","isCollapsed":false,
                  "feed":{"title":"News","source":"file:///tmp/feed.xml","articles":[]}}]
            }
            """.utf8)
        #expect(throws: SpaceLinkArchive.InvalidArchive.invalidLink) {
            try SpaceLinkArchive(data: data)
        }
    }

    @Test @MainActor func sharesOnlyTheSelectedFolderAndItsDescendants() async throws {
        let space = Space(name: "Work")
        let ancestor = try #require(space.addPinFolder(named: "Ancestor"))
        let folder = try #require(space.addPinFolder(named: "Share Me", inside: ancestor.id))
        let child = try #require(space.addPinFolder(named: "References", inside: folder.id))
        let other = try #require(space.addPinFolder(named: "Unrelated"))
        let fixtures: [(PinFolder, String)] = [(child, "first"), (other, "excluded"), (folder, "last")]
        for (destination, title) in fixtures {
            let tab = BrowserTab(url: URL(string: "https://example.com/\(title)"), title: title, isPinned: true)
            space.pinned.append(tab)
            space.setPinFolder(destination.id, for: tab)
        }
        space.today = [BrowserTab(url: URL(string: "https://example.com/today"))]

        let shared = try #require(SpaceLinkArchive(space: space, folderID: folder.id))
        let payload: Data
        if #available(macOS 15.2, iOS 18.2, *) {
            payload = try await shared.exported(as: .json)
        } else {
            payload = try shared.encoded()
        }
        let imported = try SpaceLinkArchive(data: payload).makeSpace(colorIndex: 0)
        #expect(imported.name == "Share Me")
        #expect(imported.pinFolders.map { imported.pinFolderName($0) } == ["Share Me", "Share Me / References"])
        #expect(imported.pinned.map(\.title) == ["first", "last"])
        #expect(imported.pinned.first?.pinFolderID == imported.pinFolders.last?.id)
        #expect(imported.today.isEmpty)
        #expect(SpaceLinkArchive(space: space, folderID: UUID()) == nil)
        #expect(SpaceLinkArchive(space: Space(name: "Private", isPrivate: true)) == nil)
    }
}
