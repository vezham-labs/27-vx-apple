import AppKit
import BrowserCore
import UniformTypeIdentifiers

extension Browser {
    var canExportSpaceLinks: Bool {
        let space = currentSpace
        return !space.isPrivate && space.id != Preferences.agentSpaceID
    }

    func exportSpaceLinks() {
        guard canExportSpaceLinks, let window = nsWindow, window.attachedSheet == nil else { return }
        guard let export = SpaceLinkArchive(space: currentSpace) else { return }

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
                let space = archive.makeSpace(colorIndex: library.regularSpaces.count, windowKey: windowKey)
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
