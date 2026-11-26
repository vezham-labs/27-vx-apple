import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// Portable Space links. A file contains names and URLs, free of browser session state.
public struct SpaceLinkArchive: Codable, Sendable, Transferable {
    private static let maximumBytes = 2 * 1024 * 1024
    private static let maximumLinks = 5_000

    public let version: Int
    public let name: String
    public let pinned: [Link]
    public let today: [Link]
    public let pinFolders: [PinFolder]?
    /// The profile label is portable metadata only. Cookies, history, and website data stay local.
    public let websiteProfileName: String?

    public struct Link: Codable, Sendable {
        public let title: String
        public let url: URL
        public let pinFolderID: UUID?
        public let pinnedHomeURL: URL?

        fileprivate var isWebLink: Bool {
            Self.isSafeWebURL(url)
        }

        fileprivate static func isSafeWebURL(_ url: URL) -> Bool {
            guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
                  let host = url.host(), !host.isEmpty else { return false }
            return url.user == nil && url.password == nil
        }

        @MainActor
        fileprivate init?(_ tab: BrowserTab) {
            guard !tab.isPrivate, let url = tab.url else { return nil }
            self.title = tab.displayTitle
            self.url = url
            pinFolderID = tab.isPinned ? tab.pinFolderID : nil
            pinnedHomeURL = tab.isPinned ? tab.pinnedHomeURL.flatMap { Self.isSafeWebURL($0) ? $0 : nil } : nil
            guard isWebLink else { return nil }
        }
    }

    public enum InvalidArchive: LocalizedError {
        case tooLarge, unsupportedVersion, invalidLink

        public var errorDescription: String? {
            switch self {
            case .tooLarge: "Choose an Ark Space file with at most 5,000 links, 5,000 folders, and 2 MB of data."
            case .unsupportedVersion: "This Space file uses an unsupported version."
            case .invalidLink: "The Space file contains a link that Ark cannot import."
            }
        }
    }

    @MainActor
    public init?(space: Space, folderID: UUID? = nil, websiteProfileName: String? = nil) {
        guard !space.isPrivate else { return nil }
        version = 1
        if let folderID {
            guard let folder = space.pinFolders.first(where: { $0.id == folderID }) else { return nil }
            let children = Dictionary(grouping: space.pinFolders, by: \.parentID)
            var queue = [folderID]
            var included = Set<UUID>()
            while let id = queue.popLast() {
                if included.insert(id).inserted { queue.append(contentsOf: (children[id] ?? []).map(\.id)) }
            }
            name = folder.name
            pinned = space.pinned.filter { $0.pinFolderID.map(included.contains) ?? false }.compactMap(Link.init)
            today = []
            pinFolders = space.pinFolders.filter { included.contains($0.id) }.map { record in
                var record = Self.portableFolder(record)
                if record.id == folderID { record.parentID = nil }
                return record
            }
            self.websiteProfileName = nil
        } else {
            name = space.name
            pinned = space.pinned.compactMap(Link.init)
            today = space.today.compactMap(Link.init)
            pinFolders = space.pinFolders.isEmpty ? nil : space.pinFolders.map(Self.portableFolder)
            self.websiteProfileName = Self.portableProfileName(websiteProfileName)
        }
    }

    public static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { archive in
            try archive.encoded()
        }
        .suggestedFileName("Ark Collection.json")
    }

    public init(contentsOf url: URL) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: Self.maximumBytes + 1) ?? Data()
        try self.init(data: data)
    }

    public init(data: Data) throws {
        guard data.count <= Self.maximumBytes else { throw InvalidArchive.tooLarge }
        self = try JSONDecoder().decode(Self.self, from: data)
    }

    private enum CodingKeys: String, CodingKey { case version, name, pinned, today, pinFolders, websiteProfileName }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        name = try values.decode(String.self, forKey: .name)
        pinned = try values.decode([Link].self, forKey: .pinned)
        today = try values.decode([Link].self, forKey: .today)
        pinFolders = try values.decodeIfPresent([PinFolder].self, forKey: .pinFolders)?.map(Self.portableFolder)
        websiteProfileName = Self.portableProfileName(try values.decodeIfPresent(String.self, forKey: .websiteProfileName))
        try validate()
    }

    public func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumBytes else { throw InvalidArchive.tooLarge }
        return data
    }

    private func validate() throws {
        guard version == 1 else { throw InvalidArchive.unsupportedVersion }
        guard pinned.count + today.count <= Self.maximumLinks, (pinFolders?.count ?? 0) <= Self.maximumLinks else {
            throw InvalidArchive.tooLarge
        }
        guard pinned.allSatisfy(\.isWebLink), today.allSatisfy(\.isWebLink) else { throw InvalidArchive.invalidLink }
        guard pinned.allSatisfy({ link in
            guard let url = link.pinnedHomeURL else { return true }
            return Link.isSafeWebURL(url)
        }) else { throw InvalidArchive.invalidLink }
        guard (pinFolders ?? []).allSatisfy({ folder in
            guard let feed = folder.feed else { return true }
            return LiveFolderFeed.webURL(feed.source.absoluteString) != nil
        }) else { throw InvalidArchive.invalidLink }
    }

    /// A portable subscription contains its address and label. Cached articles belong to the local Space.
    private static func portableFolder(_ record: PinFolder) -> PinFolder {
        var folder = record
        if let feed = record.feed {
            folder.feed = LiveFolderFeed(source: feed.source, title: feed.title, articles: [])
        }
        // Account-specific organization choices stay local to the source Space.
        folder.knownGitHubOwners = nil
        folder.hiddenGitHubOwners = nil
        folder.feedNeedsActivation = nil
        return folder
    }

    @MainActor
    public func makeSpace(colorIndex: Int, websiteProfileID: UUID? = nil, windowKey: UUID? = nil) -> Space {
        let name = self.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let records = pinFolders ?? []
        var folderIDs: [UUID: UUID] = [:]
        for record in records where folderIDs[record.id] == nil { folderIDs[record.id] = UUID() }
        let folders = records.compactMap { record -> PinFolder? in
            guard let id = folderIDs[record.id] else { return nil }
            var folder = PinFolder(id: id, name: record.name, parentID: record.parentID.flatMap { folderIDs[$0] },
                                   isCollapsed: record.isCollapsed)
            folder.feed = record.feed
            if record.feed != nil { folder.feedNeedsActivation = true }
            return folder
        }
        func tab(from link: Link, pinned: Bool) -> BrowserTab {
            let tab = BrowserTab(url: link.url, title: link.title, isPinned: pinned)
            tab.windowKey = windowKey
            if pinned {
                tab.pinFolderID = link.pinFolderID.flatMap { folderIDs[$0] }
                // Older portable files did not carry a separate home address.
                tab.pinnedHomeURL = link.pinnedHomeURL ?? link.url
            }
            return tab
        }
        let space = Space(name: name.isEmpty ? "Imported Space" : name, colorIndex: colorIndex,
                          pinned: pinned.map { tab(from: $0, pinned: true) },
                          today: today.map { tab(from: $0, pinned: false) })
        space.websiteProfileID = websiteProfileID
        space.restorePinFolders(folders)
        return space
    }

    /// Creates an isolated local profile when importing a portable Space that carries a label.
    /// This preserves the profile assignment without transferring or reusing website data.
    @MainActor
    public func makeImportedWebsiteProfile(in profiles: inout [WebsiteProfile]) -> UUID? {
        guard let websiteProfileName else { return nil }
        let base = String("Imported \(websiteProfileName)".prefix(70))
        let existing = Set(profiles.map { $0.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) })
        var candidate = base
        var suffix = 2
        while existing.contains(candidate.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)) {
            let ending = " \(suffix)"
            candidate = String(base.prefix(80 - ending.count)) + ending
            suffix += 1
        }
        guard let profile = WebsiteProfile(name: candidate) else { return nil }
        profiles.append(profile)
        return profile.id
    }

    private static func portableProfileName(_ name: String?) -> String? {
        guard let name, let profile = WebsiteProfile(name: name) else { return nil }
        return profile.name
    }
}
