import AppKit
import BrowserEngine
import BrowserCore
import Extensibility

/// Adding, updating and removing extensions that don't come from an app: Chrome Web Store and
/// Firefox Add-ons links, and unpacked folders. Ark keeps them current itself, once a day.
extension Library {
    /// One add, shown on the add sheet before anything runs.
    struct ExtensionPreview: Identifiable {
        var id: String { item.id }
        let item: InstalledExtension
        let manifest: ExtensionManifest
        /// Plain-language lines for the add sheet, sites folded into one.
        var permissions: [PermissionSummary] { manifest.permissionSummary }
        var isVerified: Bool { VerifiedExtensions.contains(item.source) }

        /// The manifest's largest icon, from the downloaded or picked folder.
        var icon: NSImage? {
            let folder: URL? = item.folderPath.map { URL(filePath: $0) } ?? {
                guard case .folder(let path) = item.source else { return nil }
                return URL(filePath: path)
            }()
            guard let folder, let icons = manifest.raw["icons"]?.object else { return nil }
            let best = icons.compactMap { key, value in Int(key).flatMap { size in value.string.map { (size, $0) } } }
                .max { $0.0 < $1.0 }
            return best.flatMap { NSImage(contentsOf: folder.appending(path: $0.1)) }
        }
    }

    nonisolated static let fetch: ExtensionInstaller.Fetch = { url in
        var request = URLRequest(url: url)
        request.setValue("Ark", forHTTPHeaderField: "User-Agent")
        return try await fetchRequest(request)
    }

    nonisolated static let fetchRequest: ExtensionInstaller.FetchRequest = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return data
    }

    /// /usr/bin/ditto ships with macOS and unzips into the app's own container, sandbox and all.
    nonisolated static let unzip: ExtensionInstaller.Unzip = { zip, folder in
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let p = Process()
            p.executableURL = URL(filePath: "/usr/bin/ditto")
            p.arguments = ["-x", "-k", zip.path(percentEncoded: false), folder.path(percentEncoded: false)]
            p.terminationHandler = { p in
                p.terminationStatus == 0 ? cont.resume() : cont.resume(throwing: CocoaError(.fileReadCorruptFile))
            }
            do { try p.run() } catch { cont.resume(throwing: error) }
        }
    }

    /// What the engine loads: every enabled catalog extension that has files.
    func extensionFolders() -> [ExtensionFolder] {
        extensionCatalog.enabled.compactMap { item in
            if let bookmark = item.folderBookmark {
                var stale = false
                // Outside the sandbox a folder needs no security scope, so a bookmark made inside it
                // still counts when the scope can't be started.
                guard let url = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, bookmarkDataIsStale: &stale),
                      url.startAccessingSecurityScopedResource() || !AppFolders.isSandboxed else { return nil }
                return ExtensionFolder(id: item.id, url: url)
            }
            return item.folderPath.map { ExtensionFolder(id: item.id, url: URL(filePath: $0)) }
        }
    }

    /// chrome.management must also see installs that are disabled and therefore not loaded in WebKit.
    var extensionManagementEntries: [EngineExtensionManagementEntry] {
        extensionCatalog.items.map { item in
            let folder: URL? = item.folderPath.map { URL(fileURLWithPath: $0) } ?? item.folderBookmark.flatMap { bookmark in
                var stale = false
                return try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope,
                                bookmarkDataIsStale: &stale)
            }
            let accessed = folder?.startAccessingSecurityScopedResource() ?? false
            defer { if accessed { folder?.stopAccessingSecurityScopedResource() } }
            let manifest = folder.flatMap { try? ExtensionManifest(data: Data(contentsOf: $0.appending(path: "manifest.json"))) }
            let name = folder.flatMap { manifest?.localizedName(in: $0) } ?? item.name
            let raw = manifest?.raw
            let options = raw?["options_ui"]?["page"]?.string ?? raw?["options_page"]?.string
            let icon = folder.flatMap { Self.managementIconDataURL(manifest, folder: $0) }
            let installType: String
            if case .folder = item.source { installType = "development" } else { installType = "normal" }
            return EngineExtensionManagementEntry(
                id: item.id, name: name, shortName: raw?["short_name"]?.string ?? name,
                version: manifest?.version ?? item.version, versionName: raw?["version_name"]?.string,
                description: raw?["description"]?.string ?? "", enabled: item.isEnabled,
                installType: installType, permissions: (manifest?.permissions ?? []).sorted(),
                hostPermissions: (manifest?.hostPermissions ?? []).sorted(),
                homepageURL: raw?["homepage_url"]?.string, optionsURL: options,
                offlineEnabled: raw?["offline_enabled"]?.bool ?? false, iconDataURL: icon)
        }
    }

    private static func managementIconDataURL(_ manifest: ExtensionManifest?, folder: URL) -> String? {
        guard let icons = manifest?.raw["icons"]?.object else { return nil }
        let candidate = icons.compactMap { key, value -> (Int, String)? in
            guard let size = Int(key), size <= 128, let path = value.string,
                  !path.hasPrefix("/"), !URL(fileURLWithPath: path).pathComponents.contains("..") else { return nil }
            return (size, path)
        }.max { $0.0 < $1.0 }
        guard let (_, path) = candidate else { return nil }
        let root = folder.standardizedFileURL.path(percentEncoded: false) + "/"
        let url = folder.appending(path: path).standardizedFileURL
        guard url.path(percentEncoded: false).hasPrefix(root),
              let image = NSImage(contentsOf: url), let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return nil }
        return "data:image/png;base64," + png.base64EncodedString()
    }

    /// A pasted store link ("chromewebstore.google.com/detail/…/aeblfdkhhhdcdjpifhhbdiojplfjncoa"
    /// or "addons.mozilla.org/…/ublock-origin"): downloads it for the add sheet.
    func previewExtension(link: String) async throws -> ExtensionPreview {
        guard let source = ExtensionSource(link: link) else { throw AddError.notALink }
        let (item, manifest) = try await extensionInstaller.download(source)
        return ExtensionPreview(item: item, manifest: manifest)
    }

    /// An unpacked extension folder the user picked, e.g. one they're building.
    func previewExtension(folder: URL) throws -> ExtensionPreview {
        let manifest = try ExtensionManifest(data: Data(contentsOf: folder.appending(path: "manifest.json")))
        let item = InstalledExtension(source: .folder(path: folder.path(percentEncoded: false)), name: manifest.localizedName(in: folder),
                                      version: manifest.version, folderPath: nil,
                                      folderBookmark: try? folder.bookmarkData(options: .withSecurityScope),
                                      permissions: manifest.allPermissions)
        return ExtensionPreview(item: item, manifest: manifest)
    }

    func install(_ preview: ExtensionPreview) {
        extensionCatalog.upsert(preview.item)
        reloadExtensions()
    }

    func removeExtension(id: String) {
        if let path = extensionCatalog.items.first(where: { $0.id == id })?.folderPath,
           path.hasPrefix(extensionInstaller.root.path(percentEncoded: false)) {
            try? FileManager.default.removeItem(atPath: URL(filePath: path).deletingLastPathComponent().path(percentEncoded: false))
        }
        engine.forgetExtension(id: id)
        extensionCatalog.remove(id: id)
        reloadExtensions()
    }

    func isAllowedInPrivate(_ id: String) -> Bool { engine.extensionAllowedInPrivate(id: id) }

    func setAllowedInPrivate(_ id: String, _ allowed: Bool) {
        engine.setExtension(id: id, allowedInPrivate: allowed)
    }

    func setExtension(_ id: String, enabled: Bool) {
        extensionCatalog.setEnabled(enabled, id: id)
        reloadExtensions()
    }

    func approveUpdate(id: String) {
        extensionInstaller.approvePendingUpdate(id: id, in: extensionCatalog)
        reloadExtensions()
    }

    /// Daily, from the app's timer. Updates that ask for nothing new apply quietly; the rest wait in
    /// Settings for a yes.
    func updateExtensions(force: Bool = false) async {
        let outcomes = await extensionInstaller.updateAll(in: extensionCatalog, olderThan: force ? 0 : 20 * 3600)
        if outcomes.values.contains(where: { if case .updated = $0 { true } else { false } }) { reloadExtensions() }
    }

    enum AddError: LocalizedError {
        case notALink
        var errorDescription: String? {
            "Paste a link from the Chrome Web Store or Firefox Add-ons, or an extension's ID."
        }
    }
}
