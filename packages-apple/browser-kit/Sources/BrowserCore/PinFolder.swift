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
                            && pinFolders.contains(where: { $0.id == id })) else { return }
        tab.pinFolderID = id
    }

    func restorePinFolders(_ records: [PinFolder]) {
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
