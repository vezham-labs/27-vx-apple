import Foundation
import AppKit
import SQLite3
import BrowserCore
import Suggest

// Bringing someone's things over from the browser they're leaving: bookmarks, history, and from
// Arc its spaces with their pinned and open tabs. Everything is read straight from the other
// browser's files on this Mac, and only ever read. Passwords are never touched.

/// A browser on this Mac that can be imported from.
struct ImportSource: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        /// Chrome, Edge, Vivaldi, Brave and Arc keep Chromium's profile layout under this folder.
        case chromium(dataDir: URL)
        case safari
    }

    struct Profile: Identifiable, Hashable, Sendable {
        let folder: String
        let name: String
        var id: String { folder }
    }

    let id: String
    let name: String
    let kind: Kind
    let profiles: [Profile]
    /// Arc keeps its spaces, pinned tabs and open tabs in its own sidebar file.
    var isArc: Bool { id == "arc" }
    var supportsSpaces: Bool { isArc || id == "ardia" || id == "yab" }
    var isSafari: Bool { kind == .safari }
}

/// How the import lands. The card imports with the defaults; Configure changes them.
struct ImportOptions: Hashable, Sendable {
    enum Bookmarks: String, CaseIterable, Hashable, Sendable {
        case searchAndFavourites, searchOnly, skip
        var label: String {
            switch self {
            case .searchAndFavourites: "Find them with ⌘T, and pin the top few as Favourites"
            case .searchOnly: "Just find them with ⌘T"
            case .skip: "Don't import bookmarks"
            }
        }
    }

    enum HistoryRange: String, CaseIterable, Hashable, Sendable {
        case threeMonths, year, all
        var label: String {
            switch self {
            case .threeMonths: "Last 3 months"
            case .year: "Last year"
            case .all: "Everything"
            }
        }
        var since: Date? {
            switch self {
            case .threeMonths: Calendar.current.date(byAdding: .month, value: -3, to: .now)
            case .year: Calendar.current.date(byAdding: .year, value: -1, to: .now)
            case .all: nil
            }
        }
    }

    var profile: String?
    var importBookmarks = true
    var bookmarkMode: Bookmarks = .searchAndFavourites
    var bookmarks: Bookmarks { importBookmarks ? bookmarkMode : .skip }
    var favouriteCount = 8
    var history = true
    var historyRange: HistoryRange = .threeMonths
    /// Arc only: its spaces become Ark spaces, with their pinned and open tabs.
    var arcSpaces = true
    /// Arc only: the spaces left out, by Arc's id. Empty brings them all.
    var skippedSpaces: Set<String> = []

    func includes(_ spaceID: String) -> Bool { !skippedSpaces.contains(spaceID) }

    mutating func set(_ spaceID: String, included: Bool, all: [String]) {
        if included { skippedSpaces.remove(spaceID) } else { skippedSpaces.insert(spaceID) }
        // Leaving every space out is the same as turning Spaces off.
        if Set(all).isSubset(of: skippedSpaces) { arcSpaces = false; skippedSpaces = [] }
    }
}

/// What came over, for the card's counts.
struct ImportResult: Equatable, Sendable {
    var bookmarks = 0
    var favourites = 0
    var history = 0
    var spaces = 0
    var tabs = 0
}

/// What was read, before it lands in Ark.
struct ImportedData: Sendable {
    struct Space: Sendable {
        struct Folder: Sendable {
            let sourceID: String
            let name: String
            let parentID: String?
            let isExpanded: Bool?
        }

        struct Pin: Sendable {
            let title: String
            let url: URL
            let folderID: String?
        }

        /// The other browser's own id for the space, so importing again doesn't duplicate it.
        var sourceID: String
        var name: String
        var pinned: [Pin]
        var folders: [Folder]
        var open: [(title: String, url: URL)]

        /// Imported open tabs belong to the importing window when there is one.  Without that
        /// ownership, a newly-created Space can look empty until Ark is restarted because the
        /// window deliberately only lists its own Today tabs.
        @MainActor func populate(_ space: BrowserCore.Space, windowKey: UUID? = nil) {
            var destinations: [String: UUID] = [:]
            // Ark allows three levels. Deeper Arc pins stay in the nearest created ancestor.
            for folder in folders {
                let parent = folder.parentID.flatMap { destinations[$0] }
                if let created = space.addPinFolder(named: folder.name, inside: parent) {
                    destinations[folder.sourceID] = created.id
                    if folder.isExpanded == false { space.togglePinFolder(created.id) }
                } else {
                    destinations[folder.sourceID] = parent
                }
            }
            space.pinned = pinned.map { BrowserTab(url: $0.url, title: $0.title, isPinned: true) }
            for (pin, tab) in zip(pinned, space.pinned) {
                space.setPinFolder(pin.folderID.flatMap { destinations[$0] }, for: tab)
            }
            space.today = open.map {
                let tab = BrowserTab(url: $0.url, title: $0.title)
                tab.windowKey = windowKey
                return tab
            }
        }
    }

    var bookmarks: [(title: String, url: URL)] = []
    /// The bookmarks bar, or Arc's top apps: the best candidates for Favourites.
    var bar: [(title: String, url: URL)] = []
    var history: [HistoryStore.ImportedVisit] = []
    var spaces: [Space] = []
}

enum ImportError: LocalizedError {
    case needsFullDiskAccess
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case .needsFullDiskAccess: "Ark needs Full Disk Access to read Safari's bookmarks and history."
        case .unreadable(let what): "Couldn't read \(what)."
        }
    }
}

enum BrowserImport {
    private static var support: URL { FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support") }
    static var safariFolder: URL { FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Safari") }

    // MARK: Finding browsers

    /// The browsers on this Mac with something to import, Arc and Chrome first.
    static func detect(supportRoot: URL? = nil) -> [ImportSource] {
        let fm = FileManager.default
        let chromium: [(id: String, name: String, path: String)] = [
            ("arc", "Arc", "Arc/User Data"),
            ("chrome", "Chrome", "Google/Chrome"),
            ("edge", "Edge", "Microsoft Edge"),
            ("brave", "Brave", "BraveSoftware/Brave-Browser"),
            ("vivaldi", "Vivaldi", "Vivaldi"),
            ("ardia", "Ardia", "com.ardia.browser/Chromium"),
            ("yab", "Yab", "Yab/Chromium"),
        ]
        var found: [ImportSource] = chromium.compactMap { b in
            let dir = (supportRoot ?? support).appending(path: b.path, directoryHint: .isDirectory)
            // Ardia and Yab may keep their sidebar session even when their Chromium profile
            // has neither a bookmarks nor a history database yet.  Keep that profile visible
            // so a Spaces-only import is possible.
            let sessionRoot = dir.deletingLastPathComponent()
            let hasSeparateSession = b.id == "ardia"
                ? fm.fileExists(atPath: sessionRoot.appending(path: "session.json").path)
                : b.id == "yab" && (fm.fileExists(atPath: sessionRoot.appending(path: "spaces.json").path)
                    || fm.fileExists(atPath: sessionRoot.appending(path: "session.json").path))
            let profiles = chromiumProfiles(in: dir, includeSessionOnlyProfiles: hasSeparateSession)
            guard !profiles.isEmpty else { return nil }
            return ImportSource(id: b.id, name: b.name, kind: .chromium(dataDir: dir), profiles: profiles)
        }
        if FileManager.default.fileExists(atPath: "/Applications/Safari.app") || FileManager.default.fileExists(atPath: "/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app") {
            found.append(ImportSource(id: "safari", name: "Safari", kind: .safari, profiles: []))
        }
        return found
    }

    /// Profiles from Chromium's Local State, falling back to the folders that hold bookmarks or history.
    private static func chromiumProfiles(in dir: URL, includeSessionOnlyProfiles: Bool = false) -> [ImportSource.Profile] {
        let fm = FileManager.default
        var profiles: [ImportSource.Profile] = []
        if let data = try? Data(contentsOf: dir.appending(path: "Local State")),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let cache = (json["profile"] as? [String: Any])?["info_cache"] as? [String: Any] {
            profiles = cache.compactMap { folder, value in
                let name = (value as? [String: Any])?["name"] as? String ?? folder
                return ImportSource.Profile(folder: folder, name: name)
            }
        }
        if profiles.isEmpty, (fm.fileExists(atPath: dir.appending(path: "Default").path) || includeSessionOnlyProfiles) {
            profiles = [.init(folder: "Default", name: "Default")]
        }
        return profiles
            .filter { p in
                includeSessionOnlyProfiles || ["Bookmarks", "History"].contains {
                    fm.fileExists(atPath: dir.appending(path: p.folder).appending(path: $0).path)
                }
            }
            .sorted { $0.folder == "Default" ? true : $1.folder == "Default" ? false : $0.name < $1.name }
    }

    /// Whether Ark can read Safari's files yet; false until Full Disk Access is granted.
    static var canReadSafari: Bool {
        FileManager.default.isReadableFile(atPath: safariFolder.appending(path: "Bookmarks.plist").path)
            && (try? Data(contentsOf: safariFolder.appending(path: "Bookmarks.plist"), options: .mappedIfSafe)) != nil
    }

    /// System Settings, at Privacy & Security › Full Disk Access.
    static func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Reading

    /// Reads everything the options ask for. Off the main thread: history can be large.
    static func read(_ source: ImportSource, options: ImportOptions) async throws -> ImportedData {
        try await Task.detached(priority: .userInitiated) {
            var out = ImportedData()
            switch source.kind {
            case .chromium(let dir):
                let folder = options.profile ?? source.profiles.first?.folder ?? "Default"
                let profile = dir.appending(path: folder, directoryHint: .isDirectory)
                if options.bookmarks != .skip {
                    (out.bookmarks, out.bar) = chromiumBookmarks(profile.appending(path: "Bookmarks"))
                }
                let historyFile = profile.appending(path: "History")
                if options.history, FileManager.default.fileExists(atPath: historyFile.path) {
                    out.history = try chromiumHistory(historyFile, since: options.historyRange.since)
                }
                if source.isArc {
                    let arc = arcSidebar()
                    if options.arcSpaces { out.spaces = arc.spaces }
                    // Arc's bookmarks live in its sidebar, not a Bookmarks file: its pinned tabs
                    // and top apps are the closest thing.
                    if options.bookmarks != .skip {
                        let pinned = arc.spaces.flatMap(\.pinned).map { (title: $0.title, url: $0.url) }
                        out.bookmarks += arc.topApps + pinned
                        if out.bar.isEmpty { out.bar = arc.topApps }
                    }
                } else if source.id == "ardia", options.arcSpaces {
                    let file = dir.deletingLastPathComponent().appending(path: "session.json")
                    if let handle = try? FileHandle(forReadingFrom: file) {
                        defer { try? handle.close() }
                        let data = (try? handle.read(upToCount: 10 * 1024 * 1024 + 1)) ?? Data()
                        if data.count <= 10 * 1024 * 1024 {
                            out.spaces = ardiaSpaces(data, profile: folder)
                        }
                    }
                } else if source.id == "yab", options.arcSpaces {
                    out.spaces = yabSpaces(in: dir.deletingLastPathComponent(), profile: folder)
                }
            case .safari:
                guard canReadSafari else { throw ImportError.needsFullDiskAccess }
                if options.bookmarks != .skip {
                    (out.bookmarks, out.bar) = safariBookmarks(safariFolder.appending(path: "Bookmarks.plist"))
                }
                if options.history {
                    out.history = try safariHistory(safariFolder.appending(path: "History.db"), since: options.historyRange.since)
                }
            }
            return out
        }.value
    }

    /// Yab stores a space list and a separate JSON session per space.
    static func yabSpaces(in root: URL, profile wanted: String, sharedOverride: Bool? = nil) -> [ImportedData.Space] {
        let first = "00000000-0000-0000-0000-000000000001"
        func read(_ name: String) -> Any? {
            let file = root.appending(path: name)
            guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
            defer { try? handle.close() }
            guard let data = try? handle.read(upToCount: 10 * 1024 * 1024 + 1), data.count <= 10 * 1024 * 1024 else { return nil }
            return try? JSONSerialization.jsonObject(with: data)
        }
        let listed = read("spaces.json") as? [[String: Any]]
        guard listed != nil || FileManager.default.fileExists(atPath: root.appending(path: "session.json").path) else { return [] }
        let spaces = listed?.isEmpty == false ? (listed ?? []) : [["id": first, "name": "Personal"]]
        let sharedReceipt = read("ChromiumProfiles/\(first)-shared.json") as? [String: Any]
        let sharedID = (sharedReceipt?["physical"] as? String).flatMap(UUID.init(uuidString:))?.uuidString ?? first
        let sharedFolder = "space-" + sharedID
        let sharedEnabled = sharedOverride ?? (UserDefaults(suiteName: "dev.serafim.fast")?.bool(forKey: "pins.everySpace") == true)
        let sharedRows = ((read("session-00000000-0000-0000-0000-000000000A11.json") as? [String: Any])?["tabs"] as? [[String: Any]] ?? [])
        var seenSpaceIDs = Set<String>()
        return spaces.prefix(200).compactMap { item in
            guard let rawID = item["id"] as? String, let id = UUID(uuidString: rawID)?.uuidString,
                  seenSpaceIDs.insert(id).inserted else { return nil }
            let own = item["ownSignIns"] as? Bool == true
            let signsIn = (item["signInWith"] as? String).flatMap(UUID.init(uuidString:))?.uuidString ?? id
            let receipt = read("ChromiumProfiles/\(signsIn)-named.json") as? [String: Any]
            let physical = (receipt?["physical"] as? String).flatMap(UUID.init(uuidString:))?.uuidString ?? signsIn
            let folder = own ? "space-" + physical : sharedFolder
            guard wanted.caseInsensitiveCompare(folder) == .orderedSame || (!own && wanted == "Default") else { return nil }
            let filename = id == first ? "session.json" : "session-\(id).json"
            let entries = ((read(filename) as? [String: Any])?["tabs"] as? [[String: Any]] ?? [])
            var pins: [ImportedData.Space.Pin] = [], folders: [ImportedData.Space.Folder] = []
            var seenFolders = Set<String>(), open: [(title: String, url: URL)] = []
            let rows = entries.map { ($0, false) } + (sharedEnabled && !own ? sharedRows.map { ($0, true) } : [])
            for (entry, shared) in rows.prefix(5000) {
                let isTile = !(entry["pin"] as? String ?? "").isEmpty
                if shared && !isTile { continue }
                if sharedEnabled && !own && isTile && !shared { continue }
                let kept = entry["kept"] as? Bool == true
                let candidates = [entry["home"] as? String, entry["url"] as? String]
                guard let url = candidates.compactMap({ $0.flatMap(URL.init(string:)) }).first(where: {
                    ["http", "https"].contains($0.scheme?.lowercased() ?? "") && $0.host()?.isEmpty == false && $0.user == nil && $0.password == nil
                }) else { continue }
                let title = entry["name"] as? String ?? entry["homeTitle"] as? String ?? entry["title"] as? String ?? url.host() ?? ""
                guard isTile || kept else { open.append((title, url)); continue }
                var parent: String?
                let path = (entry["folderPath"] as? [[String: Any]] ?? []).prefix(64)
                for step in path {
                    guard let folderID = step["id"] as? String, !folderID.isEmpty else { continue }
                    if seenFolders.insert(folderID).inserted { folders.append(.init(sourceID: folderID, name: step["name"] as? String ?? "Folder", parentID: parent, isExpanded: nil)) }
                    parent = folderID
                }
                if let folderID = entry["folder"] as? String, !folderID.isEmpty {
                    if seenFolders.insert(folderID).inserted { folders.append(.init(sourceID: folderID, name: entry["folderName"] as? String ?? "Folder", parentID: parent, isExpanded: nil)) }
                    parent = folderID
                }
                pins.append(.init(title: title, url: url, folderID: parent))
            }
            return ImportedData.Space(sourceID: id, name: item["name"] as? String ?? "Space", pinned: pins, folders: folders, open: open)
        }
    }

    /// Ardia's session lists profiles as Spaces and pins by tab/group ID.
    static func ardiaSpaces(_ data: Data, profile wanted: String) -> [ImportedData.Space] {
        guard data.count <= 10 * 1024 * 1024,
              let top = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let profiles = top["profiles"] as? [String: [String: Any]] else { return [] }
        func indexed(_ key: String) -> [String: [String: Any]] {
            var result: [String: [String: Any]] = [:]
            for item in (top[key] as? [[String: Any]] ?? []).prefix(10_000) {
                if let id = item["id"] as? String, result[id] == nil { result[id] = item }
            }
            return result
        }
        let tabs = indexed("tabs"), windows = indexed("windows"), groups = indexed("groups")
        var profileIDs = Set<String>()
        let order = (top["profileOrder"] as? [String] ?? []).filter { profiles[$0] != nil && profileIDs.insert($0).inserted }
        let ids = order + profiles.keys.filter { !order.contains($0) }.sorted()
        var seenWindows = Set<String>()
        var windowIDs = (top["windowOrder"] as? [String] ?? []).filter { windows[$0] != nil && seenWindows.insert($0).inserted }
        windowIDs += windows.keys.filter { !windowIDs.contains($0) }.sorted()
        if let focused = top["focusedWindowId"] as? String, windows[focused] != nil {
            windowIDs.removeAll { $0 == focused }; windowIDs.insert(focused, at: 0)
        }
        return ids.prefix(200).compactMap { id in
            guard let profile = profiles[id] else { return nil }
            let dataID = profile["dataId"] as? String ?? id
            let profileKey = dataID.lowercased() == "default" ? "Default" : "Profile \(dataID)"
            guard profileKey == wanted else { return nil }
            var pins: [ImportedData.Space.Pin] = [], folders: [ImportedData.Space.Folder] = []
            var open: [(title: String, url: URL)] = []
            var seenPins = Set<String>(), seenFolders = Set<String>(), seenOpen = Set<String>()
            func take(_ tab: [String: Any], groupMap: [String: [String: Any]], folderID: String?) {
                guard pins.count < 5000, tab["pin"] != nil || folderID != nil else { return }
                let key = tab["pinKey"] as? String ?? tab["id"] as? String ?? UUID().uuidString
                guard seenPins.insert(key).inserted else { return }
                let candidates = [tab["pinnedUrl"] as? String, tab["url"] as? String]
                guard let url = candidates.compactMap({ $0.flatMap(URL.init(string:)) }).first(where: {
                    ["http", "https"].contains($0.scheme?.lowercased() ?? "") && $0.host()?.isEmpty == false && $0.user == nil && $0.password == nil
                }) else { return }
                var chain: [(String, [String: Any])] = [], cursor = folderID, seen = Set<String>()
                while let current = cursor, chain.count < 64, seen.insert(current).inserted, let group = groupMap[current] {
                    chain.insert((current, group), at: 0); cursor = group["parentId"] as? String
                }
                var parent: String?
                for (folder, item) in chain {
                    if seenFolders.insert(folder).inserted {
                        folders.append(.init(sourceID: folder, name: item["name"] as? String ?? "Folder", parentID: parent, isExpanded: nil))
                    }
                    parent = folder
                }
                pins.append(.init(title: tab["customTitle"] as? String ?? tab["title"] as? String ?? url.host() ?? "", url: url, folderID: parent))
            }
            for window in windowIDs {
                for tabID in (windows[window]?["tabIds"] as? [String] ?? []) {
                    guard let tab = tabs[tabID], tab["profileId"] as? String == id else { continue }
                    let matching = groups.filter { $0.value["pinned"] as? Bool != false && ($0.value["tabIds"] as? [String] ?? []).contains(tabID) }
                    func depth(_ id: String) -> Int {
                        var current: String? = id, seen = Set<String>()
                        while let value = current, seen.count < 64, seen.insert(value).inserted {
                            current = groups[value]?["parentId"] as? String
                        }
                        return seen.count
                    }
                    let folder = matching.keys.sorted { left, right in
                        let a = depth(left), b = depth(right)
                        return a == b ? left < right : a < b
                    }.last
                    if tab["pin"] != nil || folder != nil {
                        take(tab, groupMap: groups, folderID: folder)
                    } else if open.count < 5000, seenOpen.insert(tabID).inserted,
                              let raw = tab["url"] as? String, let url = URL(string: raw),
                              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                              url.host()?.isEmpty == false, url.user == nil, url.password == nil {
                        open.append((tab["customTitle"] as? String ?? tab["title"] as? String ?? url.host() ?? "", url))
                    }
                }
            }
            if pins.isEmpty, let parked = (top["parkedPins"] as? [String: [String: Any]])?[id] {
                var parkedGroups: [String: [String: Any]] = [:]
                for group in parked["groups"] as? [[String: Any]] ?? [] {
                    if let key = group["id"] as? String { parkedGroups[key] = group }
                }
                for tab in parked["tabs"] as? [[String: Any]] ?? [] { take(tab, groupMap: parkedGroups, folderID: tab["groupId"] as? String) }
            }
            return ImportedData.Space(sourceID: id, name: profile["name"] as? String ?? "Space", pinned: pins, folders: folders, open: open)
        }
    }

    // MARK: Chromium

    private static func chromiumBookmarks(_ file: URL) -> ([(title: String, url: URL)], [(title: String, url: URL)]) {
        guard let data = try? Data(contentsOf: file),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let roots = json["roots"] as? [String: Any] else { return ([], []) }
        func walk(_ node: [String: Any], into list: inout [(title: String, url: URL)]) {
            if node["type"] as? String == "url", let s = node["url"] as? String, let url = URL(string: s) {
                list.append((node["name"] as? String ?? "", url))
            }
            for child in node["children"] as? [[String: Any]] ?? [] { walk(child, into: &list) }
        }
        var all: [(title: String, url: URL)] = []
        var bar: [(title: String, url: URL)] = []
        if let b = roots["bookmark_bar"] as? [String: Any] {
            // The bar's own top-level links, in order, are the Favourites candidates.
            bar = (b["children"] as? [[String: Any]] ?? []).compactMap { c in
                guard c["type"] as? String == "url", let s = c["url"] as? String, let url = URL(string: s) else { return nil }
                return (c["name"] as? String ?? "", url)
            }
        }
        for key in ["bookmark_bar", "other", "synced"] {
            if let node = roots[key] as? [String: Any] { walk(node, into: &all) }
        }
        return (all, bar)
    }

    /// Chromium keeps visit times in microseconds since 1601.
    private static func chromiumDate(_ micros: Int64) -> Date {
        Date(timeIntervalSince1970: Double(micros) / 1_000_000 - 11_644_473_600)
    }

    private static func chromiumHistory(_ file: URL, since: Date?) throws -> [HistoryStore.ImportedVisit] {
        let sinceMicros = since.map { Int64(($0.timeIntervalSince1970 + 11_644_473_600) * 1_000_000) } ?? 0
        return try query(file, sql: """
            SELECT url, title, visit_count, last_visit_time FROM urls
            WHERE hidden = 0 AND last_visit_time > \(sinceMicros)
            ORDER BY visit_count DESC LIMIT 25000
            """) { row in
            guard let url = URL(string: row.text(0)) else { return nil }
            return .init(url: url, title: row.text(1), visitCount: Int(row.int(2)), lastVisit: chromiumDate(row.int(3)), isBookmark: false)
        }
    }

    // MARK: Arc

    /// Arc's spaces with their pinned and unpinned tabs, and its top apps, from StorableSidebar.json.
    static func arcSidebar() -> (spaces: [ImportedData.Space], topApps: [(title: String, url: URL)]) {
        let file = support.appending(path: "Arc/StorableSidebar.json")
        guard let data = try? Data(contentsOf: file) else { return ([], []) }
        return arcSidebar(data)
    }

    static func arcSidebar(_ data: Data) -> (spaces: [ImportedData.Space], topApps: [(title: String, url: URL)]) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let containers = (json["sidebar"] as? [String: Any])?["containers"] as? [Any],
              let main = containers.compactMap({ $0 as? [String: Any] }).first(where: { $0["spaces"] != nil }) else { return ([], []) }
        let items = (main["items"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }
        let byID = Dictionary(items.compactMap { i in (i["id"] as? String).map { ($0, i) } }, uniquingKeysWith: { a, _ in a })

        var budget = 5_000
        func contents(of root: String, keepFolders: Bool = false) -> (pins: [ImportedData.Space.Pin], folders: [ImportedData.Space.Folder]) {
            var pins: [ImportedData.Space.Pin] = []
            var folders: [ImportedData.Space.Folder] = []
            var visited = Set<String>()
            func read(_ id: String, parentID: String?, depth: Int) {
                guard budget > 0, depth < 64, visited.insert(id).inserted, let item = byID[id] else { return }
                budget -= 1
                let payload = item["data"] as? [String: Any]
                if let tab = payload?["tab"] as? [String: Any] {
                    guard let address = tab["savedURL"] as? String, let url = URL(string: address),
                          url.scheme == "http" || url.scheme == "https" else { return }
                    let title = item["title"] as? String ?? tab["savedTitle"] as? String ?? ""
                    pins.append(.init(title: title, url: url, folderID: parentID))
                    return
                }
                var destination = parentID
                if keepFolders, depth > 0, payload?["list"] != nil {
                    let title = (item["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    folders.append(.init(sourceID: id, name: title.flatMap { $0.isEmpty ? nil : $0 } ?? "Folder",
                                         parentID: parentID, isExpanded: item["isExpanded"] as? Bool))
                    destination = id
                }
                for case let child as String in item["childrenIds"] as? [Any] ?? [] {
                    read(child, parentID: destination, depth: depth + 1)
                }
            }
            read(root, parentID: nil, depth: 0)
            return (pins, folders)
        }

        func container(_ kind: String, in space: [String: Any]) -> String? {
            for key in ["newContainerIDs", "containerIDs"] {
                let ids = space[key] as? [Any] ?? []
                for index in stride(from: 0, to: max(0, ids.count - 1), by: 2) {
                    let marker = ids[index]
                    let matches = marker as? String == kind || (marker as? [String: Any])?[kind] != nil
                    if matches, let id = ids[index + 1] as? String, byID[id] != nil {
                        return id
                    }
                }
            }
            return nil
        }

        let spaces: [ImportedData.Space] = (main["spaces"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }.compactMap { s in
            let pinned = container("pinned", in: s).map { contents(of: $0, keepFolders: true) }
            let open = container("unpinned", in: s).map { contents(of: $0).pins.map { (title: $0.title, url: $0.url) } } ?? []
            let name = (s["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Space"
            guard pinned?.pins.isEmpty == false || pinned?.folders.isEmpty == false || !open.isEmpty else { return nil }
            return ImportedData.Space(sourceID: s["id"] as? String ?? name, name: name,
                                      pinned: pinned?.pins ?? [], folders: pinned?.folders ?? [], open: open)
        }

        let topIDs = main["topAppsContainerIDs"] as? [Any] ?? []
        let topApps = topIDs.compactMap { $0 as? String }.flatMap { contents(of: $0).pins.map { ($0.title, $0.url) } }
        return (spaces, topApps)
    }

    // MARK: Safari

    private static func safariBookmarks(_ file: URL) -> ([(title: String, url: URL)], [(title: String, url: URL)]) {
        guard let data = try? Data(contentsOf: file),
              let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return ([], []) }
        func link(_ node: [String: Any]) -> (String, URL)? {
            guard node["WebBookmarkType"] as? String == "WebBookmarkTypeLeaf",
                  let s = node["URLString"] as? String, let url = URL(string: s) else { return nil }
            return ((node["URIDictionary"] as? [String: Any])?["title"] as? String ?? "", url)
        }
        func walk(_ node: [String: Any], into list: inout [(title: String, url: URL)]) {
            if node["Title"] as? String == "com.apple.ReadingList" { return }
            if let l = link(node) { list.append(l) }
            for child in node["Children"] as? [[String: Any]] ?? [] { walk(child, into: &list) }
        }
        var all: [(title: String, url: URL)] = []
        walk(root, into: &all)
        let barNode = (root["Children"] as? [[String: Any]] ?? []).first { $0["Title"] as? String == "BookmarksBar" }
        let bar = (barNode?["Children"] as? [[String: Any]] ?? []).compactMap(link)
        return (all, bar)
    }

    private static func safariHistory(_ file: URL, since: Date?) throws -> [HistoryStore.ImportedVisit] {
        // Safari counts seconds since 2001.
        let sinceRef = since?.timeIntervalSinceReferenceDate ?? 0
        return try query(file, sql: """
            SELECT i.url, v.title, i.visit_count, MAX(v.visit_time) AS last FROM history_items i
            JOIN history_visits v ON v.history_item = i.id
            GROUP BY i.id HAVING last > \(sinceRef)
            ORDER BY i.visit_count DESC LIMIT 25000
            """) { row in
            guard let url = URL(string: row.text(0)) else { return nil }
            return .init(url: url, title: row.text(1), visitCount: Int(row.int(2)),
                         lastVisit: Date(timeIntervalSinceReferenceDate: row.double(3)), isBookmark: false)
        }
    }

    // MARK: SQLite

    struct Row {
        let stmt: OpaquePointer
        func text(_ i: Int32) -> String { sqlite3_column_text(stmt, i).map { String(cString: $0) } ?? "" }
        func int(_ i: Int32) -> Int64 { sqlite3_column_int64(stmt, i) }
        func double(_ i: Int32) -> Double { sqlite3_column_double(stmt, i) }
    }

    /// Runs a query on a copy of a browser's database: the browser may be running and holding a lock.
    private static func query<T>(_ file: URL, sql: String, map: (Row) -> T?) throws -> [T] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: file.path) else { return [] }
        let tmp = fm.temporaryDirectory.appending(path: "ark-import-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }
        let copy = tmp.appending(path: file.lastPathComponent)
        do {
            try fm.copyItem(at: file, to: copy)
            for suffix in ["-wal", "-shm"] where fm.fileExists(atPath: file.path + suffix) {
                try? fm.copyItem(atPath: file.path + suffix, toPath: copy.path + suffix)
            }
        } catch {
            throw file.path.hasPrefix(safariFolder.path) ? ImportError.needsFullDiskAccess : ImportError.unreadable(file.lastPathComponent)
        }
        var db: OpaquePointer?
        guard sqlite3_open_v2(copy.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            throw ImportError.unreadable(file.lastPathComponent)
        }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { throw ImportError.unreadable(file.lastPathComponent) }
        defer { sqlite3_finalize(stmt) }
        var out: [T] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let v = map(Row(stmt: stmt)) { out.append(v) }
        }
        return out
    }
}

// MARK: - Landing it in Ark

extension Library {
    /// Lands what was read: bookmarks and history into ⌘T's index, the top bookmarks as
    /// Favourites, Arc's spaces as spaces. Tabs come in unloaded, so nothing starts loading.
    @discardableResult
    func land(_ data: ImportedData, from source: ImportSource, options: ImportOptions) async -> ImportResult {
        var result = ImportResult()
        let now = Date.now
        if options.bookmarks != .skip {
            var seen = Set<String>()
            let marks = data.bookmarks.filter { seen.insert(URLNormalizer.key(for: $0.url)).inserted }
            _ = await history.importVisits(marks.map { .init(url: $0.url, title: $0.title, visitCount: 1, lastVisit: now, isBookmark: true) })
            result.bookmarks = marks.count
            if options.bookmarks == .searchAndFavourites {
                let room = max(0, options.favouriteCount - favorites(for: nil).count)
                for b in data.bar.filter({ $0.url.scheme?.hasPrefix("http") == true }).prefix(room) where !isFavorite(b.url) {
                    addFavorite(url: b.url, title: b.title)
                    result.favourites += 1
                }
            }
        }
        if options.history {
            await history.importVisits(data.history)
            result.history = data.history.count
        }
        let importedKey = "importedSpaces"
        var already = Set(UserDefaults.standard.stringArray(forKey: importedKey) ?? [])
        for imported in data.spaces where options.includes(imported.sourceID) && !already.contains("\(source.id):\(imported.sourceID)") {
            already.insert("\(source.id):\(imported.sourceID)")
            let taken = Set(spaces.map(\.name))
            let name = taken.contains(imported.name) ? "\(imported.name) (\(source.name))" : imported.name
            let space = addSpace()
            space.name = name
            imported.populate(space, windowKey: activeWindow?.windowKey)
            result.spaces += 1
            result.tabs += imported.pinned.count + imported.open.count
        }
        UserDefaults.standard.set(Array(already), forKey: importedKey)
        scheduleSave()
        return result
    }
}
