import AppKit
import BrowserCore
import UniformTypeIdentifiers

private struct SpacesBackup: Codable {
    struct SpaceEntry: Codable {
        let links: SpaceLinkArchive
        let symbol: String?
        let colorIndex: Int?
        let themeHue: Double?
        let themeShade: Double?
        let appearance: String?
        let order: Int?
        var safe: Bool {
            (symbol.map { !$0.isEmpty && $0.count <= 100 } ?? true)
                && (colorIndex.map { (-10000...10000).contains($0) } ?? true)
                && (themeHue.map { $0.isFinite && (0...360).contains($0) } ?? true)
                && (themeShade.map { $0.isFinite && (0...1).contains($0) } ?? true)
                && (appearance.map { $0 == "light" || $0 == "dark" } ?? true)
                && (order.map { (0...10000).contains($0) } ?? true)
        }

        @MainActor init?(_ space: Space, profileName: String?, order: Int) {
            guard let links = SpaceLinkArchive(space: space, websiteProfileName: profileName) else { return nil }
            self.links = links
            symbol = space.symbol
            colorIndex = space.colorIndex
            themeHue = space.themeHue
            themeShade = space.themeShade
            appearance = space.appearance
            self.order = order
        }

        init(from decoder: any Decoder) throws {
            if let container = try? decoder.container(keyedBy: CodingKeys.self), container.contains(.links) {
                links = try container.decode(SpaceLinkArchive.self, forKey: .links)
                symbol = try container.decodeIfPresent(String.self, forKey: .symbol)
                colorIndex = try container.decodeIfPresent(Int.self, forKey: .colorIndex)
                themeHue = try container.decodeIfPresent(Double.self, forKey: .themeHue)
                themeShade = try container.decodeIfPresent(Double.self, forKey: .themeShade)
                appearance = try container.decodeIfPresent(String.self, forKey: .appearance)
                order = try container.decodeIfPresent(Int.self, forKey: .order)
            } else {
                links = try SpaceLinkArchive(from: decoder)
                symbol = nil; colorIndex = nil; themeHue = nil; themeShade = nil; appearance = nil; order = nil
            }
        }
    }
    struct FavoriteLink: Codable {
        let title: String
        let url: URL
        var safe: Bool {
            guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
                  let host = url.host(), !host.isEmpty else { return false }
            return url.user == nil && url.password == nil
        }
    }
    struct Profile: Codable {
        let name: String?
        let favorites: [FavoriteLink]
        let spaces: [SpaceEntry]
    }
    let format: String
    let version: Int
    let profiles: [Profile]

    func validate() throws {
        guard format == "ark-spaces", version == 1, profiles.count <= 100,
              profiles.reduce(0, { $0 + $1.spaces.count }) <= 500,
              profiles.allSatisfy({ $0.favorites.count <= 5000 && $0.favorites.allSatisfy(\.safe)
                  && $0.spaces.allSatisfy(\.safe) && ($0.name.map { WebsiteProfile(name: $0) != nil } ?? true) }) else {
            throw SpaceLinkArchive.InvalidArchive.invalidLink
        }
    }
}

private enum SpacesBackupExportError: LocalizedError {
    case missingProfile(String)

    var errorDescription: String? {
        switch self {
        case .missingProfile(let space):
            "The website profile for \(space) is missing. Assign a profile in Spaces settings, then try again."
        }
    }
}

extension Browser {
    func allSpacesBackupData() throws -> Data {
        let profiles: [(UUID?, String?)] = [(nil, nil)] + library.settings.websiteProfiles.map { ($0.id, $0.name) }
        let knownProfiles = Set(library.settings.websiteProfiles.map(\.id))
        let exportSpaces = library.regularSpaces.filter { $0.id != Preferences.agentSpaceID }
        if let orphan = library.regularSpaces.first(where: { space in
            space.id != Preferences.agentSpaceID && (space.websiteProfileID.map { !knownProfiles.contains($0) } ?? false)
        }) { throw SpacesBackupExportError.missingProfile(orphan.name) }
        let backup = SpacesBackup(format: "ark-spaces", version: 1, profiles: profiles.compactMap { id, name in
            let spaces = exportSpaces.enumerated().compactMap { index, space in
                space.websiteProfileID == id ? SpacesBackup.SpaceEntry(space, profileName: name, order: index) : nil
            }
            let favorites = library.sortedFavorites(for: id).map { SpacesBackup.FavoriteLink(title: $0.customName ?? $0.title, url: $0.url) }
                .filter(\.safe)
            return spaces.isEmpty && favorites.isEmpty ? nil : SpacesBackup.Profile(name: name, favorites: favorites, spaces: spaces)
        })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(backup)
        guard data.count <= 10 * 1024 * 1024 else { throw SpaceLinkArchive.InvalidArchive.tooLarge }
        // Reuse the import validation, including each nested SpaceLinkArchive's decoder.
        let decoded = try JSONDecoder().decode(SpacesBackup.self, from: data)
        try decoded.validate()
        return data
    }

    func exportAllSpacesBackup() {
        guard let window = nsWindow, window.attachedSheet == nil else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Ark Spaces.json"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                guard let self else { return }
                try self.allSpacesBackupData().write(to: url, options: .atomic)
                self.showToast("Spaces exported")
            } catch let error as SpacesBackupExportError {
                self?.showToast(error.localizedDescription)
            } catch { self?.showToast("Couldn’t export Spaces") }
        }
    }

    func importAllSpacesBackup() {
        guard let window = nsWindow, window.attachedSheet == nil else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do {
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                let data = try handle.read(upToCount: 10 * 1024 * 1024 + 1) ?? Data()
                guard data.count <= 10 * 1024 * 1024 else { throw SpaceLinkArchive.InvalidArchive.tooLarge }
                try self.restoreAllSpacesBackup(data)
                showToast("Spaces imported")
            } catch { showToast("Couldn’t import Spaces") }
        }
    }

    func restoreAllSpacesBackup(_ data: Data) throws {
                guard data.count <= 10 * 1024 * 1024 else { throw SpaceLinkArchive.InvalidArchive.tooLarge }
                let backup = try JSONDecoder().decode(SpacesBackup.self, from: data)
                try backup.validate()
                var profiles = library.settings.websiteProfiles
                var plans: [(SpacesBackup.Profile, UUID?)] = []
                for profile in backup.profiles {
                    let profileID: UUID?
                    if let name = profile.name {
                        let base = String("Imported \(name)".prefix(70))
                        let existing = Set(profiles.map { $0.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) })
                        var candidate = base
                        var suffix = 2
                        while existing.contains(candidate.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)) {
                            let ending = " \(suffix)"
                            candidate = String(base.prefix(80 - ending.count)) + ending
                            suffix += 1
                        }
                        guard let imported = WebsiteProfile(name: candidate) else { throw SpaceLinkArchive.InvalidArchive.invalidLink }
                        profiles.append(imported)
                        profileID = imported.id
                    } else { profileID = nil }
                    plans.append((profile, profileID))
                }
                library.settings.websiteProfiles = profiles
                var restoredSpaces: [(order: Int?, sequence: Int, space: Space)] = []
                for (profile, profileID) in plans {
                    for favorite in profile.favorites { library.addFavorite(url: favorite.url, title: favorite.title, profileID: profileID) }
                    for entry in profile.spaces {
                        let space = entry.links.makeSpace(colorIndex: entry.colorIndex ?? library.regularSpaces.count, websiteProfileID: profileID, windowKey: windowKey)
                        if let symbol = entry.symbol, !symbol.isEmpty, symbol.count <= 100 { space.symbol = symbol }
                        space.themeHue = entry.themeHue
                        space.themeShade = entry.themeShade
                        if entry.appearance == "light" || entry.appearance == "dark" { space.appearance = entry.appearance }
                        restoredSpaces.append((entry.order, restoredSpaces.count, space))
                    }
                }
                restoredSpaces.sort { left, right in
                    (left.order ?? left.sequence, left.sequence) < (right.order ?? right.sequence, right.sequence)
                }
                for item in restoredSpaces { library.spaces.insert(item.space, at: library.regularSpaces.count) }
                library.scheduleSave()
    }

    /// Portable bookmarks for all regular Spaces; account data and internal pages never leave Ark.
    func allSpacesBookmarksHTML() -> String {
        func escape(_ value: String) -> String {
            value.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
        }
        var output = "<!DOCTYPE NETSCAPE-Bookmark-file-1>\n<META HTTP-EQUIV=\"Content-Type\" CONTENT=\"text/html; charset=UTF-8\">\n<TITLE>Ark Spaces</TITLE>\n<H1>Ark Spaces</H1>\n<DL><p>\n"
        func line(_ depth: Int, _ value: String) { output += String(repeating: "    ", count: depth) + value + "\n" }
        func link(_ entry: SpaceLinkArchive.Link, depth: Int, pinned: Bool) {
            let url = pinned ? (entry.pinnedHomeURL ?? entry.url) : entry.url
            line(depth, "<DT><A HREF=\"\(escape(url.absoluteString))\">\(escape(entry.title.isEmpty ? url.absoluteString : entry.title))</A>")
        }
        let exportSpaces = library.regularSpaces.filter { $0.id != Preferences.agentSpaceID }
        let profiles: [(UUID?, String)] = [(nil, "Default")] + library.settings.websiteProfiles.map { ($0.id, $0.name) }
        for (profileID, profile) in profiles {
            let favorites = library.favorites(for: profileID).sorted { $0.order < $1.order }.filter { favorite in
                guard let scheme = favorite.url.scheme?.lowercased(), ["http", "https"].contains(scheme),
                      let host = favorite.url.host(), !host.isEmpty else { return false }
                return favorite.url.user == nil && favorite.url.password == nil
            }
            guard !favorites.isEmpty else { continue }
            line(1, "<DT><H3>\(escape("Favorites (\(profile))"))</H3>")
            line(1, "<DL><p>")
            for favorite in favorites {
                let title = favorite.customName ?? (favorite.title.isEmpty ? favorite.url.absoluteString : favorite.title)
                line(2, "<DT><A HREF=\"\(escape(favorite.url.absoluteString))\">\(escape(title))</A>")
            }
            line(1, "</DL><p>")
        }
        for space in exportSpaces {
            guard let archive = SpaceLinkArchive(space: space) else { continue }
            line(1, "<DT><H3>\(escape(archive.name))</H3>")
            line(1, "<DL><p>")
            let folders = archive.pinFolders ?? []
            let ids = Set(folders.map(\.id))
            func contents(_ parent: UUID?, depth: Int, seen: Set<UUID>) {
                for folder in folders where (parent == nil ? (folder.parentID.map { !ids.contains($0) } ?? true) : folder.parentID == parent) && !seen.contains(folder.id) {
                    line(depth, "<DT><H3>\(escape(folder.name))</H3>")
                    line(depth, "<DL><p>")
                    contents(folder.id, depth: depth + 1, seen: seen.union([folder.id]))
                    line(depth, "</DL><p>")
                }
                for pin in archive.pinned where parent == nil ? (pin.pinFolderID.map { !ids.contains($0) } ?? true) : pin.pinFolderID == parent {
                    link(pin, depth: depth, pinned: true)
                }
            }
            contents(nil, depth: 2, seen: [])
            if !archive.today.isEmpty {
                line(2, "<DT><H3>Open Tabs</H3>")
                line(2, "<DL><p>")
                for tab in archive.today { link(tab, depth: 3, pinned: false) }
                line(2, "</DL><p>")
            }
            line(1, "</DL><p>")
        }
        output += "</DL><p>\n"
        return output
    }

    func exportAllSpacesBookmarks() {
        guard let window = nsWindow, window.attachedSheet == nil else { return }
        let html = allSpacesBookmarksHTML()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = "Ark Spaces.html"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try Data(html.utf8).write(to: url, options: .atomic)
                self?.showToast("Spaces exported")
            } catch { self?.showToast("Couldn’t export Spaces") }
        }
    }

    var canExportSpaceLinks: Bool {
        let space = currentSpace
        return !space.isPrivate && space.id != Preferences.agentSpaceID
    }

    func exportSpaceLinks() {
        guard canExportSpaceLinks, let window = nsWindow, window.attachedSheet == nil else { return }
        guard let export = SpaceLinkArchive(space: currentSpace,
                                            websiteProfileName: library.websiteProfileName(for: currentSpace)) else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Ark Space.json"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try export.encoded().write(to: url, options: .atomic)
                self?.showToast("Space links exported")
            } catch {
                self?.showToast("Couldn’t export Space links")
            }
        }
    }

    func importSpaceLinks() {
        guard let window = nsWindow, window.attachedSheet == nil else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do {
                let archive = try SpaceLinkArchive(contentsOf: url)
                let profileID = archive.makeImportedWebsiteProfile(in: &library.settings.websiteProfiles)
                let space = archive.makeSpace(colorIndex: library.regularSpaces.count,
                                              websiteProfileID: profileID, windowKey: windowKey)
                library.spaces.insert(space, at: library.regularSpaces.count)
                library.scheduleSave()
                showToast("Imported \(space.name)")
            } catch let error as SpaceLinkArchive.InvalidArchive {
                showToast(error.localizedDescription)
            } catch {
                showToast("Couldn’t read the Ark Space file")
            }
        }
    }
}
