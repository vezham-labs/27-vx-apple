import Foundation

public struct PinFolder: Codable, Equatable, Identifiable, Sendable {
    static let maxDepth = 3
    public let id: UUID
    public internal(set) var name: String
    public internal(set) var parentID: UUID?
    public internal(set) var isCollapsed: Bool
    public internal(set) var feed: LiveFolderFeed?
    var feedNeedsActivation: Bool?

    init(id: UUID = UUID(), name: String, parentID: UUID? = nil, isCollapsed: Bool = false) {
        self.id = id
        self.name = name
        self.parentID = parentID
        self.isCollapsed = isCollapsed
    }
}

extension Space {
    public var rootPins: [BrowserTab] { pinned.filter { $0.pinFolderID == nil } }

    public func pinFolderName(_ folder: PinFolder) -> String {
        var names = [folder.name]
        var parentID = folder.parentID
        while let id = parentID, let parent = pinFolders.first(where: { $0.id == id }) {
            names.append(parent.name)
            parentID = parent.parentID
        }
        return names.reversed().joined(separator: " / ")
    }

    public func canNestPinFolder(in id: UUID) -> Bool {
        var depth = 0
        var current: UUID? = id
        while let folderID = current, let folder = pinFolders.first(where: { $0.id == folderID }) {
            depth += 1
            current = folder.parentID
        }
        return depth > 0 && depth < PinFolder.maxDepth
    }

    @discardableResult
    public func addPinFolder(named name: String, inside parentID: UUID? = nil) -> PinFolder? {
        guard !isPrivate, let name = Self.validFolderName(name),
              parentID.map(canNestPinFolder) ?? true else { return nil }
        let folder = PinFolder(name: name, parentID: parentID)
        pinFolders.append(folder)
        return folder
    }

    public func renamePinFolder(_ id: UUID, to name: String) {
        guard let index = pinFolders.firstIndex(where: { $0.id == id }),
              let name = Self.validFolderName(name) else { return }
        pinFolders[index].name = name
    }

    public func togglePinFolder(_ id: UUID) {
        guard let index = pinFolders.firstIndex(where: { $0.id == id }) else { return }
        pinFolders[index].isCollapsed.toggle()
    }

    /// Deleting a folder lifts its direct children to the parent without changing pin order.
    public func removePinFolder(_ id: UUID) {
        guard let index = pinFolders.firstIndex(where: { $0.id == id }) else { return }
        liveFolderRefreshTimes.removeValue(forKey: id)
        let parent = pinFolders.remove(at: index).parentID
        for index in pinFolders.indices where pinFolders[index].parentID == id {
            pinFolders[index].parentID = parent
        }
        for tab in pinned where tab.pinFolderID == id { tab.pinFolderID = parent }
    }

    /// Reorders a folder among its siblings or nests it in another folder.
    /// `beforeID` is a sibling in the destination; nil places the folder last.
    @discardableResult
    public func movePinFolder(_ id: UUID, into parentID: UUID?, before beforeID: UUID? = nil) -> Bool {
        guard !isPrivate, pinFolders.contains(where: { $0.id == id }), beforeID != id else { return false }
        let recordsByID = Dictionary(uniqueKeysWithValues: pinFolders.map { ($0.id, $0) })
        let childrenByParent = Dictionary(grouping: pinFolders, by: \.parentID)
        if let parentID {
            guard let parent = recordsByID[parentID], parent.feed == nil else { return false }
        }

        var descendants: Set<UUID> = [id]
        var frontier = [id]
        while let current = frontier.popLast() {
            for child in childrenByParent[current] ?? [] {
                if descendants.insert(child.id).inserted { frontier.append(child.id) }
            }
        }
        guard parentID.map({ !descendants.contains($0) }) ?? true else { return false }

        var subtreeHeight = 1
        var levels: [(UUID, Int)] = [(id, 1)]
        var heightVisited: Set<UUID> = []
        while let (current, depth) = levels.popLast() {
            guard heightVisited.insert(current).inserted else { continue }
            subtreeHeight = max(subtreeHeight, depth)
            for child in childrenByParent[current] ?? [] { levels.append((child.id, depth + 1)) }
        }

        var parentDepth = 0
        var ancestor = parentID
        var ancestorVisited: Set<UUID> = []
        while let current = ancestor {
            guard ancestorVisited.insert(current).inserted,
                  let record = recordsByID[current] else { return false }
            parentDepth += 1
            ancestor = record.parentID
        }
        guard parentDepth + subtreeHeight <= PinFolder.maxDepth else { return false }
        if let beforeID {
            guard let before = recordsByID[beforeID], before.parentID == parentID else { return false }
        }

        var updated = pinFolders
        guard let index = updated.firstIndex(where: { $0.id == id }) else { return false }
        var moved = updated.remove(at: index)
        moved.parentID = parentID
        let insertion: Int
        if let beforeID, let before = updated.firstIndex(where: { $0.id == beforeID }) {
            insertion = before
        } else {
            insertion = updated.lastIndex(where: { $0.parentID == parentID }).map { $0 + 1 } ?? updated.endIndex
        }
        updated.insert(moved, at: insertion)
        guard updated != pinFolders else { return false }
        pinFolders = updated
        return true
    }

    /// Applies the destination for a dragged folder over a folder heading.
    /// The top and bottom bands reorder it; the middle of a regular folder nests it.
    @discardableResult
    public func movePinFolder(_ id: UUID, relativeTo targetID: UUID, verticalFraction: Double) -> Bool {
        guard let target = pinFolders.first(where: { $0.id == targetID }), targetID != id else { return false }
        if target.feed != nil || verticalFraction < 0.30 {
            return movePinFolder(id, into: target.parentID, before: target.id)
        }
        if verticalFraction <= 0.70 {
            return movePinFolder(id, into: target.id)
        }
        let siblings = pinFolders.filter { $0.parentID == target.parentID }
        let next = siblings.firstIndex { $0.id == target.id }.flatMap { index in
            siblings.dropFirst(index + 1).first
        }
        return movePinFolder(id, into: target.parentID, before: next?.id)
    }

    @discardableResult
    public func addLiveFolder(address: String, inside parentID: UUID? = nil) async throws -> PinFolder? {
        guard !isPrivate, parentID.map(canNestPinFolder) ?? true else { return nil }
        let feed = try await LiveFolderFeed.load(address: address)
        try Task.checkCancellation()
        guard let folder = addPinFolder(named: feed.title, inside: parentID),
              let index = pinFolders.firstIndex(where: { $0.id == folder.id }) else { return nil }
        pinFolders[index].feed = feed
        liveFolderRefreshTimes[folder.id] = .now
        return pinFolders[index]
    }

    /// A failed or cancelled refresh leaves the cached articles intact.
    @discardableResult
    public func refreshLiveFolder(_ id: UUID, minimumAge: TimeInterval = 0, allowActivation: Bool = true) async throws -> Bool {
        guard !isPrivate,
              let folder = pinFolders.first(where: { $0.id == id }), let oldFeed = folder.feed,
              allowActivation || folder.feedNeedsActivation != true,
              Date.now.timeIntervalSince(liveFolderRefreshTimes[id] ?? .distantPast) >= minimumAge,
              refreshingLiveFolderIDs.insert(id).inserted else { return false }
        defer { refreshingLiveFolderIDs.remove(id) }
        let feed = try await LiveFolderFeed.load(address: oldFeed.source.absoluteString)
        try Task.checkCancellation()
        guard let index = pinFolders.firstIndex(where: { $0.id == id && $0.feed == oldFeed }) else { return false }
        liveFolderRefreshTimes[id] = .now
        guard feed != oldFeed || folder.feedNeedsActivation == true else { return false }
        pinFolders[index].feed = feed
        pinFolders[index].feedNeedsActivation = nil
        return true
    }

    public func setPinFolder(_ id: UUID?, for tab: BrowserTab) {
        guard id == nil || (!isPrivate && pinned.contains(where: { $0 === tab })
                            && pinFolders.contains(where: { $0.id == id && $0.feed == nil })) else { return }
        tab.pinFolderID = id
    }

    /// Moves a pinned tab into a folder and optionally places it beside another pinned tab.
    @discardableResult
    public func movePinnedTab(_ id: UUID, into folderID: UUID?, relativeTo targetID: UUID? = nil,
                              after: Bool = false) -> Bool {
        guard !isPrivate, let sourceIndex = pinned.firstIndex(where: { $0.id == id }), id != targetID else { return false }
        if let folderID {
            guard pinFolders.contains(where: { $0.id == folderID && $0.feed == nil }) else { return false }
        }
        if let targetID {
            guard let target = pinned.first(where: { $0.id == targetID }), target.pinFolderID == folderID else { return false }
        }

        let originalOrder = pinned.map(\.id)
        let originalFolder = pinned[sourceIndex].pinFolderID
        var updated = pinned
        let tab = updated.remove(at: sourceIndex)
        let insertion: Int
        if let targetID, let targetIndex = updated.firstIndex(where: { $0.id == targetID }) {
            insertion = targetIndex + (after ? 1 : 0)
        } else if let lastInFolder = updated.lastIndex(where: { $0.pinFolderID == folderID }) {
            insertion = lastInFolder + 1
        } else {
            insertion = updated.endIndex
        }
        updated.insert(tab, at: insertion)
        guard updated.map(\.id) != originalOrder || originalFolder != folderID else { return false }
        tab.pinFolderID = folderID
        pinned = updated
        return true
    }

    public func restorePinFolders(_ records: [PinFolder]) {
        var seen = Set<UUID>()
        pinFolders = isPrivate ? [] : records.filter { seen.insert($0.id).inserted }
        let parents = Dictionary(uniqueKeysWithValues: pinFolders.map { ($0.id, $0.parentID) })
        for index in pinFolders.indices {
            let folder = pinFolders[index]
            var visited = Set([folder.id])
            var parent = folder.parentID
            while let id = parent {
                guard visited.count < PinFolder.maxDepth, visited.insert(id).inserted, let next = parents[id] else {
                    pinFolders[index].parentID = nil
                    break
                }
                parent = next
            }
        }
        for tab in pinned {
            if let id = tab.pinFolderID, !parents.keys.contains(id) { tab.pinFolderID = nil }
        }
        for tab in today { tab.pinFolderID = nil }
    }

    private static func validFolderName(_ input: String) -> String? {
        let name = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : String(name.prefix(100))
    }
}
