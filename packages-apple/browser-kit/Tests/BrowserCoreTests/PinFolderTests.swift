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

    @Test @MainActor func movesFoldersAmongSiblingsAndIntoFoldersWithoutCyclesOrExcessDepth() throws {
        let space = Space(name: "Work")
        let first = try #require(space.addPinFolder(named: "First"))
        let second = try #require(space.addPinFolder(named: "Second"))
        let third = try #require(space.addPinFolder(named: "Third"))
        let child = try #require(space.addPinFolder(named: "Child", inside: first.id))
        let grandchild = try #require(space.addPinFolder(named: "Grandchild", inside: child.id))

        #expect(space.movePinFolder(third.id, into: nil, before: first.id))
        #expect(space.pinFolders.filter { $0.parentID == nil }.map(\.name) == ["Third", "First", "Second"])
        #expect(space.movePinFolder(second.id, into: first.id))
        #expect(space.pinFolders.first { $0.id == second.id }?.parentID == first.id)
        #expect(space.movePinFolder(second.id, into: first.id, before: child.id))
        #expect(space.pinFolders.filter { $0.parentID == first.id }.map(\.name) == ["Second", "Child"])
        #expect(!space.movePinFolder(first.id, into: child.id))
        #expect(!space.movePinFolder(third.id, into: grandchild.id))
        #expect(!space.movePinFolder(child.id, into: second.id, before: third.id))
    }

    @Test @MainActor func draggedFoldersReorderAboveAndBelowOrNestInTheMiddle() throws {
        let space = Space(name: "Work")
        let first = try #require(space.addPinFolder(named: "First"))
        let second = try #require(space.addPinFolder(named: "Second"))
        let third = try #require(space.addPinFolder(named: "Third"))

        #expect(space.movePinFolder(third.id, relativeTo: first.id, verticalFraction: 0.1))
        #expect(space.pinFolders.filter { $0.parentID == nil }.map(\.name) == ["Third", "First", "Second"])
        #expect(space.movePinFolder(second.id, relativeTo: first.id, verticalFraction: 0.5))
        #expect(space.pinFolders.first { $0.id == second.id }?.parentID == first.id)
        #expect(space.movePinFolder(second.id, relativeTo: first.id, verticalFraction: 0.9))
        #expect(space.pinFolders.filter { $0.parentID == nil }.map(\.name) == ["Third", "First", "Second"])
    }

    @Test @MainActor func draggedPinsReorderWithinAndAcrossFolders() throws {
        let first = BrowserTab(url: nil, title: "First", isPinned: true)
        let second = BrowserTab(url: nil, title: "Second", isPinned: true)
        let third = BrowserTab(url: nil, title: "Third", isPinned: true)
        let space = Space(name: "Work", pinned: [first, second, third])
        let folder = try #require(space.addPinFolder(named: "Reading"))
        space.setPinFolder(folder.id, for: first)
        space.setPinFolder(folder.id, for: second)

        #expect(space.movePinnedTab(first.id, into: folder.id, relativeTo: second.id, after: true))
        #expect(space.pinned.filter { $0.pinFolderID == folder.id }.map(\.id) == [second.id, first.id])

        #expect(space.movePinnedTab(third.id, into: folder.id, relativeTo: first.id))
        #expect(space.pinned.filter { $0.pinFolderID == folder.id }.map(\.id) == [second.id, third.id, first.id])
        #expect(space.movePinnedTab(third.id, into: nil))
        #expect(space.rootPins.map(\.id) == [third.id])
        #expect(space.pinned.filter { $0.pinFolderID == folder.id }.map(\.id) == [second.id, first.id])
    }

    @Test @MainActor func movesSeveralPinsInSidebarOrderAndRestoresTheirOrganization() throws {
        let first = BrowserTab(url: nil, title: "First", isPinned: true)
        let second = BrowserTab(url: nil, title: "Second", isPinned: true)
        let third = BrowserTab(url: nil, title: "Third", isPinned: true)
        let fourth = BrowserTab(url: nil, title: "Fourth", isPinned: true)
        let space = Space(name: "Work", pinned: [first, second, third, fourth])
        let reading = try #require(space.addPinFolder(named: "Reading"))
        let later = try #require(space.addPinFolder(named: "Later"))
        space.setPinFolder(reading.id, for: first)
        space.setPinFolder(later.id, for: second)
        let beforeTabs = space.pinned
        let beforeFolders = space.pinFolders
        var beforeFoldersByTab: [UUID: UUID?] = [:]
        for tab in beforeTabs { beforeFoldersByTab.updateValue(tab.pinFolderID, forKey: tab.id) }

        #expect(space.movePinnedTabs([first.id, third.id], into: later.id)?.map(\.id) == [first.id, third.id])
        #expect(space.pinned.map(\.id) == [second.id, first.id, third.id, fourth.id])
        #expect(space.pinned.filter { $0.pinFolderID == later.id }.map(\.id) == [second.id, first.id, third.id])

        #expect(space.restorePinnedOrganization(beforeTabs, folders: beforeFolders, folderIDs: beforeFoldersByTab))
        #expect(space.pinned.map(\.id) == [first.id, second.id, third.id, fourth.id])
        #expect(space.pinned.map(\.pinFolderID) == [reading.id, later.id, nil, nil])
        #expect(space.pinFolders == beforeFolders)
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
