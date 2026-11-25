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
        var shareOpenTabs: Bool?
        var deviceTabsPublishedAt: Date?
        var withdrawDeviceTabs: Bool?
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
    public private(set) var otherDevices: [BrowserSyncRemoteDevice] = []

    @ObservationIgnored private let configurationURL: URL?
    @ObservationIgnored private var configuration: Configuration
    @ObservationIgnored private let worker = BrowserSyncFolderWorker()
    @ObservationIgnored private var lastDeviceTabsContent: String?

    public var isConfigured: Bool { configuration.folderBookmark != nil }
    public var sharesOpenTabs: Bool { configuration.shareOpenTabs ?? false }

    public init(configurationURL: URL?) {
        self.configurationURL = configurationURL
        if let configurationURL, let data = try? Data(contentsOf: configurationURL),
           let saved = try? JSONDecoder().decode(Configuration.self, from: data) {
            configuration = saved
        } else {
            configuration = Configuration(deviceID: UUID(), folderBookmark: nil, folderName: nil,
                                          lastSyncedAt: nil, shareOpenTabs: false, deviceTabsPublishedAt: nil,
                                          withdrawDeviceTabs: false)
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
        // Tab sharing consent is scoped to the selected sync folder. Selecting
        // a destination must never carry open-page sharing into a new folder.
        configuration.shareOpenTabs = false
        configuration.deviceTabsPublishedAt = nil
        configuration.withdrawDeviceTabs = false
        lastDeviceTabsContent = nil
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
        otherDevices = []
        try? persistConfiguration()
    }

    /// Open-page URLs and titles are private by default and only shared after an explicit opt-in.
    public func setSharingOpenTabs(_ enabled: Bool) {
        guard sharesOpenTabs != enabled else { return }
        let hasPublishedTabs = configuration.deviceTabsPublishedAt != nil || lastDeviceTabsContent != nil
        configuration.shareOpenTabs = enabled
        configuration.deviceTabsPublishedAt = nil
        configuration.withdrawDeviceTabs = !enabled && hasPublishedTabs
        lastDeviceTabsContent = nil
        try? persistConfiguration()
    }

    /// Merges this snapshot with the selected folder without blocking the UI
    /// actor. The caller decides how to apply the returned snapshot to live tabs.
    public func synchronize(_ snapshot: BrowserSnapshot) async -> BrowserSnapshot? {
        guard let bookmark = configuration.folderBookmark else { return nil }
        state = .syncing
        let deviceID = configuration.deviceID
        let deviceName = ProcessInfo.processInfo.hostName
        let shouldPublishDeviceTabs = sharesOpenTabs || configuration.withdrawDeviceTabs == true
        let content: String?
        if shouldPublishDeviceTabs {
            guard let value = BrowserSyncItems.deviceTabsValue(
                from: snapshot, deviceID: deviceID, deviceName: deviceName,
                sharing: sharesOpenTabs, updatedAt: .distantPast
            ) else {
                state = .failed("Couldn’t prepare this device’s tab list.")
                return nil
            }
            content = value
        } else {
            content = nil
        }
        let now = Date()
        let heartbeatDue = configuration.deviceTabsPublishedAt.map { now.timeIntervalSince($0) >= 15 * 60 } ?? true
        let refreshDeviceTabs = shouldPublishDeviceTabs && (content != lastDeviceTabsContent || heartbeatDue)
        let publishedAt = refreshDeviceTabs ? now : (configuration.deviceTabsPublishedAt ?? now)
        let deviceTabsValue: String?
        if shouldPublishDeviceTabs {
            guard let value = BrowserSyncItems.deviceTabsValue(
                from: snapshot, deviceID: deviceID, deviceName: deviceName,
                sharing: sharesOpenTabs, updatedAt: publishedAt
            ) else {
                state = .failed("Couldn’t prepare this device’s tab list.")
                return nil
            }
            deviceTabsValue = value
        } else {
            deviceTabsValue = nil
        }
        do {
            let result = try await worker.synchronize(snapshot, bookmark: bookmark, deviceID: deviceID,
                                                      deviceName: deviceName, deviceTabsValue: deviceTabsValue)
            if let renewed = result.renewedBookmark { configuration.folderBookmark = renewed }
            if sharesOpenTabs {
                if refreshDeviceTabs { configuration.deviceTabsPublishedAt = now }
                lastDeviceTabsContent = content
            } else if configuration.withdrawDeviceTabs == true {
                configuration.deviceTabsPublishedAt = nil
                configuration.withdrawDeviceTabs = false
                lastDeviceTabsContent = nil
            }
            configuration.lastSyncedAt = .now
            otherDevices = result.otherDevices
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

public struct BrowserSyncRemoteTab: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let url: URL
}

public struct BrowserSyncRemoteSpace: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let tabs: [BrowserSyncRemoteTab]
}

public struct BrowserSyncRemoteDevice: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let updatedAt: Date
    public let spaces: [BrowserSyncRemoteSpace]
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
        let otherDevices: [BrowserSyncRemoteDevice]
    }

    func synchronize(_ snapshot: BrowserSnapshot, bookmark: Data, deviceID: UUID,
                     deviceName: String, deviceTabsValue: String?) throws -> Result {
        let resolved = try BrowserSyncCoordinator.resolveBookmark(bookmark)
        let folder = resolved.url
        let started = folder.startAccessingSecurityScopedResource()
        defer { if started { folder.stopAccessingSecurityScopedResource() } }

        var localValues = BrowserSyncItems.values(from: snapshot)
        if let deviceTabsValue {
            localValues["deviceTabs:\(deviceID.uuidString.lowercased())"] = deviceTabsValue
        }
        let ownDeviceTabsKey = "deviceTabs:\(deviceID.uuidString.lowercased())"
        let merged = try BrowserSyncFolderTransport.synchronize(
            in: folder,
            scope: "browser",
            deviceID: deviceID,
            deviceName: deviceName,
            current: localValues,
            protectedPrefixes: ["space:", "deviceTabs:"],
            understands: { key, value in
                // Each device owns one tab-index key; missing peer keys are not local deletions.
                if key.hasPrefix("deviceTabs:"), key != ownDeviceTabsKey { return false }
                return BrowserSyncItems.understands(key: key, value: value)
            }
        )
        let renewed = resolved.isStale ? try BrowserSyncCoordinator.makeBookmark(for: folder) : nil
        return Result(snapshot: BrowserSyncItems.applying(merged, to: snapshot), renewedBookmark: renewed,
                      otherDevices: BrowserSyncItems.otherDevices(in: merged, excluding: deviceID))
    }
}
