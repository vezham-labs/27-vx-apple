import Foundation

/// Exchanges one device's merged view through a user-selected shared folder.
/// The caller owns folder selection, security-scoped access and scheduling.
public enum BrowserSyncFolderTransport {
    public static let maximumFileSize = 4 * 1_024 * 1_024
    public static let maximumPeerFiles = 256

    public enum TransportError: Error, Equatable {
        case invalidScope
        case folderUnavailable
        case folderIsNotDirectory
        case tooManyPeerFiles
        case deviceFileTooLarge
        case invalidDeviceFile
        case writeFailed
    }

    /// Reads only Ark files for this scope, merges their entries, and atomically
    /// writes this device's merged view. Each device owns a separate file, so
    /// simultaneous passes do not overwrite one another's edits.
    ///
    /// The caller must start and stop security-scoped access for `folderURL` on
    /// platforms that require it. A folder may be on iCloud Drive or another
    /// file provider; this method never contacts a network service directly.
    @discardableResult
    public static func synchronize(
        in folderURL: URL,
        scope: String,
        deviceID: UUID,
        deviceName: String? = nil,
        current: [String: String],
        now: Date = Date(),
        protectedPrefixes: [String] = [],
        protectedCollectionFloor: Int = 5,
        understands: (String, String) -> Bool = { _, _ in true }
    ) throws -> [String: String] {
        guard isValidComponent(scope) else { throw TransportError.invalidScope }
        guard folderURL.isFileURL else { throw TransportError.folderUnavailable }
        let values = try folderURL.resourceValues(forKeys: [.isDirectoryKey])
        guard values.isDirectory == true else { throw TransportError.folderIsNotDirectory }

        let fm = FileManager.default
        let ownURL = fileURL(in: folderURL, scope: scope, deviceID: deviceID)
        let prefix = "ark-browser-sync-v1-\(scope)-"
        let files = try fm.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ).filter {
            $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension == "json"
        }
        guard files.count <= maximumPeerFiles else { throw TransportError.tooManyPeerFiles }

        var ownFile: BrowserSyncFile?
        var peers: [[String: BrowserSyncEntry]] = []
        for url in files {
            let resource = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard resource?.isRegularFile == true, resource?.isSymbolicLink != true else { continue }
            let data = try coordinatedRead(url)
            guard data.count <= maximumFileSize else {
                if url == ownURL { throw TransportError.deviceFileTooLarge }
                continue
            }
            guard let file = BrowserSyncMerge.decode(data, scope: scope),
                  let fileDeviceID = UUID(uuidString: file.deviceID),
                  url.lastPathComponent == fileURL(in: folderURL, scope: scope,
                                                   deviceID: fileDeviceID).lastPathComponent else {
                // Keep foreign, partial, and newer-format files untouched.
                continue
            }
            if file.deviceID.caseInsensitiveCompare(deviceID.uuidString) == .orderedSame {
                guard url == ownURL else { continue }
                ownFile = file
            } else {
                peers.append(file.entries)
            }
        }

        // A present but unreadable/corrupt own file must not be treated as a new
        // device: doing so could turn an incomplete snapshot into deletions.
        if fm.fileExists(atPath: ownURL.path), ownFile == nil {
            let ownResource = try? ownURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard ownResource?.isRegularFile == true, ownResource?.isSymbolicLink != true else {
                throw TransportError.invalidDeviceFile
            }
            let data = try coordinatedRead(ownURL)
            guard data.count <= maximumFileSize,
                  let file = BrowserSyncMerge.decode(data, scope: scope),
                  file.deviceID.caseInsensitiveCompare(deviceID.uuidString) == .orderedSame else {
                throw data.count > maximumFileSize ? TransportError.deviceFileTooLarge : TransportError.invalidDeviceFile
            }
            ownFile = file
        }

        let merged = BrowserSyncMerge.pass(
            current: current,
            base: ownFile?.entries,
            peers: peers,
            deviceID: deviceID.uuidString.lowercased(),
            now: now.timeIntervalSince1970,
            protectedPrefixes: protectedPrefixes,
            protectedCollectionFloor: protectedCollectionFloor,
            understands: understands
        )
        let file = BrowserSyncFile(
            deviceID: deviceID.uuidString.lowercased(),
            deviceName: deviceName.map { String($0.prefix(128)) },
            scope: scope,
            writtenAt: now.timeIntervalSince1970.isFinite ? now.timeIntervalSince1970 : 0,
            entries: merged
        )
        guard let data = BrowserSyncMerge.encode(file), data.count <= maximumFileSize else {
            throw TransportError.deviceFileTooLarge
        }
        try coordinatedWrite(data, to: ownURL)
        return BrowserSyncMerge.live(merged)
    }

    private static func fileURL(in folder: URL, scope: String, deviceID: UUID) -> URL {
        folder.appending(path: "ark-browser-sync-v1-\(scope)-\(deviceID.uuidString.lowercased()).json")
    }

    private static func isValidComponent(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".."
            && value.utf8.allSatisfy { byte in
                (byte >= 48 && byte <= 57) || (byte >= 65 && byte <= 90)
                    || (byte >= 97 && byte <= 122) || byte == 45 || byte == 46 || byte == 95
            }
    }

    private static func coordinatedRead(_ url: URL) throws -> Data {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var result: Result<Data, Error>?
        coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError) { coordinatedURL in
            result = Result { try Data(contentsOf: coordinatedURL, options: [.mappedIfSafe]) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw TransportError.invalidDeviceFile }
        return try result.get()
    }

    private static func coordinatedWrite(_ data: Data, to url: URL) throws {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var writeError: Error?
        let options: NSFileCoordinator.WritingOptions = FileManager.default.fileExists(atPath: url.path)
            ? .forReplacing : .forMerging
        coordinator.coordinate(writingItemAt: url, options: options, error: &coordinationError) { coordinatedURL in
            do { try data.write(to: coordinatedURL, options: .atomic) }
            catch { writeError = error }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
        guard FileManager.default.fileExists(atPath: url.path) else { throw TransportError.writeFailed }
    }
}
