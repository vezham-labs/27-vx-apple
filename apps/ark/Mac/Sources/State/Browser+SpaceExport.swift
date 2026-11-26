import AppKit
import BrowserCore
import UniformTypeIdentifiers

extension Browser {
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
        for space in library.regularSpaces where space.id != Preferences.agentSpaceID {
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
