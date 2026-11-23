import Foundation

/// A single synced value. A nil value is a tombstone so deletions survive
/// until every device has had time to observe them.
public struct BrowserSyncEntry: Codable, Equatable, Sendable {
    public var value: String?
    public var timestamp: Double
    public var deviceID: String

    public init(value: String?, timestamp: Double, deviceID: String) {
        self.value = value
        self.timestamp = timestamp
        self.deviceID = deviceID
    }
}

/// One device's last merged view for a scope. Devices write separate files;
/// merging these files never relies on directory enumeration order.
public struct BrowserSyncFile: Codable, Equatable, Sendable {
    public static let currentFormat = 1

    public var format: Int
    public var deviceID: String
    public var deviceName: String?
    public var scope: String
    public var writtenAt: Double
    public var entries: [String: BrowserSyncEntry]

    public init(format: Int = Self.currentFormat, deviceID: String, deviceName: String? = nil,
                scope: String, writtenAt: Double, entries: [String: BrowserSyncEntry]) {
        self.format = format
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.scope = scope
        self.writtenAt = writtenAt
        self.entries = entries
    }
}

/// Deterministic, storage-independent merge rules for Ark's future sync
/// transports. This layer only handles small keyed values; platform code owns
/// folder access, device identity, and when a sync pass runs.
public enum BrowserSyncMerge {
    public static let format = BrowserSyncFile.currentFormat
    public static let tombstoneLifetime: TimeInterval = 365 * 24 * 60 * 60

    /// A total ordering: all devices choose the same value for the same maps.
    public static func wins(_ candidate: BrowserSyncEntry, over existing: BrowserSyncEntry) -> Bool {
        if candidate.timestamp != existing.timestamp { return candidate.timestamp > existing.timestamp }
        if candidate.deviceID != existing.deviceID { return candidate.deviceID > existing.deviceID }
        switch (candidate.value, existing.value) {
        case (nil, nil): return false
        case (nil, _): return true
        case (_, nil): return false
        case let (candidate?, existing?): return candidate > existing
        }
    }

    public static func merge(_ maps: [[String: BrowserSyncEntry]]) -> [String: BrowserSyncEntry] {
        var result: [String: BrowserSyncEntry] = [:]
        for map in maps {
            for (key, entry) in map where result[key].map({ wins(entry, over: $0) }) ?? true {
                result[key] = entry
            }
        }
        return result
    }

    /// Stamps local edits over the last agreed map. Unknown values are kept
    /// verbatim and never tombstoned, allowing older clients to round-trip
    /// fields introduced by a newer client.
    public static func stamp(current: [String: String], base: [String: BrowserSyncEntry], deviceID: String,
                             now: TimeInterval, joining: Bool = false,
                             protectedPrefixes: [String] = [], protectedCollectionFloor: Int = 5,
                             understands: (String, String) -> Bool = { _, _ in true }) -> [String: BrowserSyncEntry] {
        let previousTime = base.values.map(\.timestamp).filter(\.isFinite).max() ?? 0
        let clock = joining ? 0 : max(now.isFinite ? now : 0, previousTime + 0.001)
        var result = base

        for (key, value) in current where base[key]?.value != value {
            result[key] = BrowserSyncEntry(value: value, timestamp: clock, deviceID: deviceID)
        }

        let lostCollections = Set(protectedPrefixes.filter { prefix in
            !current.keys.contains { $0.hasPrefix(prefix) }
                && base.filter { $0.key.hasPrefix(prefix) && $0.value.value != nil }.count >= protectedCollectionFloor
        })
        for (key, entry) in base {
            guard let value = entry.value, current[key] == nil, understands(key, value),
                  !lostCollections.contains(where: { key.hasPrefix($0) }) else { continue }
            result[key] = BrowserSyncEntry(value: nil, timestamp: clock, deviceID: deviceID)
        }
        return result
    }

    /// Applies one sync pass: stamp local changes, merge peers, and expire old
    /// tombstones. A device joining an existing folder starts at timestamp 0,
    /// so its initial values do not overwrite values already in that folder.
    public static func pass(current: [String: String], base: [String: BrowserSyncEntry]?,
                            peers: [[String: BrowserSyncEntry]], deviceID: String, now: TimeInterval,
                            protectedPrefixes: [String] = [], protectedCollectionFloor: Int = 5,
                            understands: (String, String) -> Bool = { _, _ in true }) -> [String: BrowserSyncEntry] {
        let local = stamp(current: current, base: base ?? [:], deviceID: deviceID, now: now,
                          joining: base == nil && !peers.isEmpty, protectedPrefixes: protectedPrefixes,
                          protectedCollectionFloor: protectedCollectionFloor, understands: understands)
        return prune(merge([local] + peers), now: now)
    }

    public static func live(_ entries: [String: BrowserSyncEntry]) -> [String: String] {
        entries.compactMapValues(\.value)
    }

    public static func prune(_ entries: [String: BrowserSyncEntry], now: TimeInterval) -> [String: BrowserSyncEntry] {
        guard now.isFinite else { return entries }
        return entries.filter { $0.value.value != nil || $0.value.timestamp >= now - tombstoneLifetime }
    }

    /// Rejects damaged, foreign, and wrong-scope files. Invalid individual
    /// entries are dropped while valid and unknown entries remain available.
    public static func decode(_ data: Data, scope: String) -> BrowserSyncFile? {
        guard var file = try? JSONDecoder().decode(BrowserSyncFile.self, from: data),
              file.format == format, file.scope == scope, !file.deviceID.isEmpty else { return nil }
        file.entries = file.entries.filter {
            $0.value.timestamp.isFinite && $0.value.timestamp >= 0 && !$0.value.deviceID.isEmpty
        }
        return file
    }

    public static func encode(_ file: BrowserSyncFile) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(file)
    }

    /// Canonical JSON text so dictionary key order does not look like an edit.
    public static func text<T: Encodable>(_ value: T) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) }
    }

    public static func value<T: Decodable>(_ type: T.Type, from text: String) -> T? {
        try? JSONDecoder().decode(type, from: Data(text.utf8))
    }
}
