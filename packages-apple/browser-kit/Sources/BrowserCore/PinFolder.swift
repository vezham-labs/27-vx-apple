import Foundation

public struct PinFolder: Codable, Equatable, Identifiable, Sendable {
    static let maxDepth = 3
    public let id: UUID
    public internal(set) var name: String
    public internal(set) var parentID: UUID?
    public internal(set) var isCollapsed: Bool
    public internal(set) var feed: LiveFolderFeed?
    var feedNeedsActivation: Bool?
    var knownGitHubOwners: [String]?
    var hiddenGitHubOwners: [String]?

    /// Remember owners even when hidden or absent from the latest refresh, so they can be restored.
    public var githubOwners: [String] {
        guard let feed, feed.isGitHubPullRequests else { return [] }
        return Array(Set((knownGitHubOwners ?? []) + feed.articles.compactMap { Self.githubOwner($0.url) })).sorted()
    }

    public var visibleArticles: [LiveFolderFeed.Article] {
        guard let feed else { return [] }
        guard feed.isGitHubPullRequests, let hiddenGitHubOwners, !hiddenGitHubOwners.isEmpty else { return feed.articles }
        let hidden = Set(hiddenGitHubOwners)
        return feed.articles.filter { Self.githubOwner($0.url).map { !hidden.contains($0) } ?? true }
    }

    public func showsGitHubOwner(_ owner: String) -> Bool { !(hiddenGitHubOwners ?? []).contains(owner.lowercased()) }

    fileprivate static func githubOwner(_ url: URL) -> String? {
        guard url.scheme?.lowercased() == "https", url.host()?.lowercased() == "github.com" else { return nil }
        let parts = url.path().split(separator: "/")
        guard parts.count >= 4, parts[2].lowercased() == "pull" else { return nil }
        return parts[0].lowercased()
    }

    init(id: UUID = UUID(), name: String, parentID: UUID? = nil, isCollapsed: Bool = false) {
        self.id = id
        self.name = name
        self.parentID = parentID
        self.isCollapsed = isCollapsed
    }
}

extension Space {
    public func setGitHubOwner(_ owner: String, shown: Bool, in folderID: UUID) {
        guard let index = pinFolders.firstIndex(where: { $0.id == folderID && $0.feed?.isGitHubPullRequests == true }) else { return }
        let normalized = owner.lowercased()
        let owners = pinFolders[index].githubOwners
        guard owners.contains(normalized) else { return }
        // Older saved folders may not have a remembered-owner list yet.
        pinFolders[index].knownGitHubOwners = owners
        var hidden = Set(pinFolders[index].hiddenGitHubOwners ?? [])
        if shown { hidden.remove(normalized) } else { hidden.insert(normalized) }
        pinFolders[index].hiddenGitHubOwners = hidden.isEmpty ? nil : hidden.sorted()
    }

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
              !oldFeed.isGitHubPullRequests,
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

    public var automaticGitHubFolderID: UUID? {
        pinFolders.first {
            $0.feed?.isGitHubPullRequests == true && $0.feedNeedsActivation != true
        }?.id
    }

    /// An explicit request can create or resume a folder. A scheduled request can only update its original folder.
    @discardableResult
    public func refreshGitHubPullRequests(cookies: [HTTPCookie], existingFolderID: UUID? = nil) async throws -> PinFolder? {
        try await refreshGitHubPullRequests(existingFolderID: existingFolderID) {
            try await LiveFolderFeed.loadGitHubPullRequests(cookies: cookies)
        }
    }

    @discardableResult
    func refreshGitHubPullRequests(existingFolderID: UUID? = nil, load: () async throws -> LiveFolderFeed) async throws -> PinFolder? {
        guard !isPrivate else { return nil }
        let original = pinFolders.first { $0.feed?.isGitHubPullRequests == true }
        let refreshID = original?.id ?? id
        if let existingFolderID {
            guard automaticGitHubFolderID == existingFolderID,
                  Date.now.timeIntervalSince(liveFolderRefreshTimes[existingFolderID] ?? .distantPast) >= 900 else { return nil }
        }
        guard refreshingLiveFolderIDs.insert(refreshID).inserted else { return nil }
        defer { refreshingLiveFolderIDs.remove(refreshID) }
        let profileID = websiteProfileID
        try Task.checkCancellation()
        let feed = try await load()
        try Task.checkCancellation()
        guard websiteProfileID == profileID else { return nil }
        if let index = pinFolders.firstIndex(where: { $0.feed?.isGitHubPullRequests == true }) {
            let folder = pinFolders[index]
            guard folder.id == original?.id else { return nil }
            if let existingFolderID {
                guard folder.id == existingFolderID, folder.feed == original?.feed,
                      folder.feedNeedsActivation != true else { return nil }
            }
            liveFolderRefreshTimes[folder.id] = .now
            let owners = Array(Set(folder.githubOwners + feed.articles.compactMap { PinFolder.githubOwner($0.url) })).sorted()
            if existingFolderID != nil, folder.feed == feed, owners == (folder.knownGitHubOwners ?? []) { return nil }
            pinFolders[index].feed = feed
            pinFolders[index].knownGitHubOwners = owners.isEmpty ? nil : owners
            pinFolders[index].feedNeedsActivation = nil
            return pinFolders[index]
        }
        guard existingFolderID == nil, original == nil else { return nil }
        guard let folder = addPinFolder(named: feed.title), let index = pinFolders.firstIndex(where: { $0.id == folder.id }) else { return nil }
        pinFolders[index].feed = feed
        pinFolders[index].knownGitHubOwners = pinFolders[index].githubOwners
        liveFolderRefreshTimes[folder.id] = .now
        return pinFolders[index]
    }

    public func setPinFolder(_ id: UUID?, for tab: BrowserTab) {
        guard id == nil || (!isPrivate && pinned.contains(where: { $0 === tab })
                            && pinFolders.contains(where: { $0.id == id && $0.feed == nil })) else { return }
        tab.pinFolderID = id
    }

    /// Moves several pinned tabs as one sidebar operation, preserving their current sidebar order.
    /// Live folders cannot own manually moved pins.
    @discardableResult
    public func movePinnedTabs(_ orderedIDs: [UUID], into folderID: UUID?) -> [BrowserTab]? {
        var ids = Set(orderedIDs)
        guard !isPrivate, !ids.isEmpty, ids.count == orderedIDs.count else { return nil }
        for id in orderedIDs {
            if let members = splitGroup(in: pinned), members.contains(where: { $0.id == id }) {
                ids.formUnion(members.map(\.id))
            }
        }
        if let folderID, !pinFolders.contains(where: { $0.id == folderID && $0.feed == nil }) { return nil }
        let moving = pinned.filter { ids.contains($0.id) }
        guard moving.count == ids.count else { return nil }
        let unchanged = moving.allSatisfy { $0.pinFolderID == folderID }
        guard !unchanged else { return nil }

        var updated = pinned.filter { !ids.contains($0.id) }
        let insertion = updated.lastIndex(where: { $0.pinFolderID == folderID }).map { $0 + 1 } ?? updated.endIndex
        for tab in moving { tab.pinFolderID = folderID }
        updated.insert(contentsOf: moving, at: insertion)
        pinned = updated
        return moving
    }

    /// Restores one immediately preceding pin-folder operation if the pin set is still the same.
    @discardableResult
    public func restorePinnedOrganization(_ tabs: [BrowserTab], folders: [PinFolder],
                                          folderIDs: [UUID: UUID?]) -> Bool {
        guard !isPrivate, Set(tabs.map(\.id)) == Set(pinned.map(\.id)) else { return false }
        for tab in tabs {
            if let folderID = folderIDs[tab.id] ?? nil,
               !folders.contains(where: { $0.id == folderID && $0.feed == nil }) { return false }
        }
        restorePinFolders(folders)
        for tab in tabs { tab.pinFolderID = folderIDs[tab.id] ?? nil }
        pinned = tabs
        return true
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

        let group = splitGroup(in: pinned).flatMap { $0.contains(where: { $0.id == id }) ? $0 : nil } ?? [pinned[sourceIndex]]
        let ids = Set(group.map(\.id))
        guard targetID.map({ !ids.contains($0) }) ?? true else { return false }
        let originalOrder = pinned.map(\.id)
        let originalFolder = pinned[sourceIndex].pinFolderID
        let moving = pinned.filter { ids.contains($0.id) }
        var updated = pinned.filter { !ids.contains($0.id) }
        let insertion: Int
        if let targetID, let targetIndex = updated.firstIndex(where: { $0.id == targetID }) {
            insertion = targetIndex + (after ? 1 : 0)
        } else if let lastInFolder = updated.lastIndex(where: { $0.pinFolderID == folderID }) {
            insertion = lastInFolder + 1
        } else {
            insertion = updated.endIndex
        }
        updated.insert(contentsOf: moving, at: insertion)
        guard updated.map(\.id) != originalOrder || originalFolder != folderID else { return false }
        for tab in moving { tab.pinFolderID = folderID }
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
