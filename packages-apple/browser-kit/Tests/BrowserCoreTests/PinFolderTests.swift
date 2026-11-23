import Foundation
import Testing
@testable import BrowserCore

struct PinFolderTests {
    @Test @MainActor func nestedFoldersRoundTripAndRemovalPreservesPins() throws {
        let first = BrowserTab(url: nil, title: "First", isPinned: true)
        let second = BrowserTab(url: nil, title: "Second", isPinned: true)
        let space = Space(name: "Work", pinned: [first, second])
        let parent = try #require(space.addPinFolder(named: " Research "))
        let child = try #require(space.addPinFolder(named: "References", inside: parent.id))
        space.setPinFolder(child.id, for: first)
        space.togglePinFolder(parent.id)
        #expect(space.rootPins.map(\.id) == [second.id])

        let data = try JSONEncoder().encode(space.record)
        let restored = Space(try JSONDecoder().decode(SpaceRecord.self, from: data))
        #expect(restored.pinFolders == space.pinFolders)
        #expect(restored.pinned.map(\.id) == [first.id, second.id])
        #expect(restored.pinned.first?.pinFolderID == child.id)
        restored.removePinFolder(parent.id)
        #expect(restored.pinFolders.first?.parentID == nil)
        restored.removePinFolder(child.id)
        #expect(restored.rootPins.map(\.id) == [first.id, second.id])
    }

    @Test @MainActor func repairsCyclicParentsAndMissingMembership() throws {
        let tab = BrowserTab(url: nil, isPinned: true)
        let space = Space(name: "Work", pinned: [tab])
        let first = UUID()
        let second = UUID()
        var record = space.record
        record.pinFolders = [PinFolder(id: first, name: "First", parentID: second),
                             PinFolder(id: second, name: "Second", parentID: first)]
        record.pinned[0].pinFolderID = UUID()
        let restored = Space(record)
        #expect(restored.pinFolders.allSatisfy { $0.parentID == nil })
        #expect(restored.rootPins.first?.id == tab.id)
    }

    @Test @MainActor func portableLinksRecreateFoldersWithFreshIDs() throws {
        let url = try #require(URL(string: "https://example.com/reference"))
        let tab = BrowserTab(url: url, isPinned: true)
        let original = Space(name: "Work", pinned: [tab])
        let parent = try #require(original.addPinFolder(named: "Work"))
        let folder = try #require(original.addPinFolder(named: "Reference", inside: parent.id))
        original.setPinFolder(folder.id, for: tab)
        let archive = try #require(SpaceLinkArchive(space: original))
        let restored = try SpaceLinkArchive(data: archive.encoded()).makeSpace(colorIndex: 0)
        let newFolder = try #require(restored.pinFolders.first { $0.name == folder.name })
        #expect(newFolder.id != folder.id)
        #expect(restored.pinFolderName(newFolder) == "Work / Reference")
        #expect(restored.pinned.first?.pinFolderID == newFolder.id)
    }

    @Test @MainActor func legacySpacesDecodeAndPrivateSpacesRejectFolders() throws {
        let original = Space(name: "Personal", pinned: [BrowserTab(url: nil, isPinned: true)])
        let data = try JSONEncoder().encode(original.record)
        let restored = Space(try JSONDecoder().decode(SpaceRecord.self, from: data))
        #expect(restored.pinFolders.isEmpty)
        #expect(restored.rootPins.map(\.id) == original.pinned.map(\.id))
        #expect(Space(name: "Private", isPrivate: true).addPinFolder(named: "Private") == nil)
    }
}
