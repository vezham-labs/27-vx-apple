import Foundation
import Observation

/// Local device configuration and shared-folder sync status for Ark.
@MainActor @Observable
public final class BrowserSyncCoordinator {
    private struct Configuration: Codable {
        var deviceID: UUID
        var folderBookmark: Data?
        var folderName: String?
        var lastSyncedAt: Date?
    }

    public enum State: Equatable {
        case off
        case ready
        case syncing
        case synced(Date)
        case failed(String)
    }

    public private(set) var state: State
    public private(set) var folderName: String?
    public private(set) var lastSyncedAt: Date?

    @ObservationIgnored private let configurationURL: URL?
    @ObservationIgnored private var configuration: Configuration
    @ObservationIgnored private let worker = BrowserSyncFolderWorker()

    public var isConfigured: Bool { configuration.folderBookmark != nil }

    public init(configurationURL: URL?) {
        self.configurationURL = configurationURL
        if let configurationURL, let data = try? Data(contentsOf: configurationURL),
           let saved = try? JSONDecoder().decode(Configuration.self, from: data) {
            configuration = saved
        } else {
            configuration = Configuration(deviceID: UUID(), folderBookmark: nil, folderName: nil, lastSyncedAt: nil)
        }
        folderName = configuration.folderName
        lastSyncedAt = configuration.lastSyncedAt
        state = configuration.folderBookmark == nil ? .off : .ready
    }

    /// Remembers access to the folder the user selected in Ark's file picker.
    public func selectFolder(_ url: URL) throws {
        guard url.isFileURL,
              try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
            throw BrowserSyncCoordinatorError.notAFolder
        }
        let started = url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }
        configuration.folderBookmark = try Self.makeBookmark(for: url)
        configuration.folderName = url.lastPathComponent
        configuration.lastSyncedAt = nil
        folderName = configuration.folderName
        lastSyncedAt = nil
        state = .ready
        try persistConfiguration()
    }

    public func disconnect() {
        configuration.folderBookmark = nil
        configuration.folderName = nil
        configuration.lastSyncedAt = nil
        folderName = nil
        lastSyncedAt = nil
        state = .off
        try? persistConfiguration()
    }

    /// Merges this snapshot with the selected folder without blocking the UI
    /// actor. The caller decides how to apply the returned snapshot to live tabs.
    public func synchronize(_ snapshot: BrowserSnapshot) async -> BrowserSnapshot? {
        guard let bookmark = configuration.folderBookmark else { return nil }
        state = .syncing
        let deviceID = configuration.deviceID
        do {
            let result = try await worker.synchronize(snapshot, bookmark: bookmark, deviceID: deviceID)
            if let renewed = result.renewedBookmark { configuration.folderBookmark = renewed }
            configuration.lastSyncedAt = .now
            lastSyncedAt = configuration.lastSyncedAt
            state = .synced(configuration.lastSyncedAt ?? .now)
            try persistConfiguration()
            return result.snapshot
        } catch {
            state = .failed(error.localizedDescription)
            return nil
        }
    }

    private func persistConfiguration() throws {
        guard let configurationURL else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(configuration)
        try FileManager.default.createDirectory(
            at: configurationURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try data.write(to: configurationURL, options: .atomic)
    }

    nonisolated fileprivate static func makeBookmark(for url: URL) throws -> Data {
        #if os(macOS)
        try url.bookmarkData(options: .withSecurityScope)
        #else
        try url.bookmarkData(options: .minimalBookmark)
        #endif
    }

    nonisolated fileprivate static func resolveBookmark(_ data: Data) throws -> (url: URL, isStale: Bool) {
        var isStale = false
        #if os(macOS)
        let url = try URL(resolvingBookmarkData: data, options: .withSecurityScope,
                          relativeTo: nil, bookmarkDataIsStale: &isStale)
        #else
        let url = try URL(resolvingBookmarkData: data, options: [],
                          relativeTo: nil, bookmarkDataIsStale: &isStale)
        #endif
        return (url, isStale)
    }
}

public enum BrowserSyncCoordinatorError: Error {
    case notAFolder
}

extension BrowserSyncCoordinatorError: LocalizedError {
    public var errorDescription: String? { "Choose a shared folder." }
}

private actor BrowserSyncFolderWorker {
    struct Result: Sendable {
        let snapshot: BrowserSnapshot
        let renewedBookmark: Data?
    }

    func synchronize(_ snapshot: BrowserSnapshot, bookmark: Data, deviceID: UUID) throws -> Result {
        let resolved = try BrowserSyncCoordinator.resolveBookmark(bookmark)
        let folder = resolved.url
        let started = folder.startAccessingSecurityScopedResource()
        defer { if started { folder.stopAccessingSecurityScopedResource() } }

        let localValues = BrowserSyncItems.values(from: snapshot)
        let merged = try BrowserSyncFolderTransport.synchronize(
            in: folder,
            scope: "browser",
            deviceID: deviceID,
            deviceName: ProcessInfo.processInfo.hostName,
            current: localValues,
            protectedPrefixes: ["space:"],
            understands: { BrowserSyncItems.understands(key: $0, value: $1) }
        )
        let renewed = resolved.isStale ? try BrowserSyncCoordinator.makeBookmark(for: folder) : nil
        return Result(snapshot: BrowserSyncItems.applying(merged, to: snapshot), renewedBookmark: renewed)
    }
}
