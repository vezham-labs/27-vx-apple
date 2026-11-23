import Foundation
import Testing
@testable import BrowserCore

@Test func syncMergeIsIndependentOfPeerOrder() {
    let maps: [[String: BrowserSyncEntry]] = [
        ["space:1": .init(value: "one", timestamp: 4, deviceID: "A")],
        ["space:1": .init(value: "two", timestamp: 5, deviceID: "B"),
         "space:2": .init(value: "new", timestamp: 2, deviceID: "B")],
        ["space:2": .init(value: "other", timestamp: 3, deviceID: "C")],
    ]
    #expect(BrowserSyncMerge.merge(maps) == BrowserSyncMerge.merge(maps.reversed()))
    #expect(BrowserSyncMerge.live(BrowserSyncMerge.merge(maps)) == ["space:1": "two", "space:2": "other"])
}

@Test func syncTombstoneWinsTimestampAndDeviceTies() {
    let deleted = BrowserSyncEntry(value: nil, timestamp: 3, deviceID: "A")
    let live = BrowserSyncEntry(value: "value", timestamp: 3, deviceID: "A")
    #expect(BrowserSyncMerge.wins(deleted, over: live))
    #expect(!BrowserSyncMerge.wins(live, over: deleted))
}

@Test func syncPassPreservesConcurrentEditsAndPropagatesDeletion() {
    let base: [String: BrowserSyncEntry] = [
        "space:1": .init(value: "old", timestamp: 10, deviceID: "A"),
        "space:2": .init(value: "remove", timestamp: 10, deviceID: "A"),
    ]
    let peer: [String: BrowserSyncEntry] = [
        "space:1": .init(value: "peer edit", timestamp: 12, deviceID: "B"),
        "space:3": .init(value: "added elsewhere", timestamp: 12, deviceID: "B"),
    ]
    let merged = BrowserSyncMerge.pass(current: ["space:1": "local edit"], base: base, peers: [peer],
                                       deviceID: "A", now: 11)
    #expect(BrowserSyncMerge.live(merged) == ["space:1": "peer edit", "space:3": "added elsewhere"])
    #expect(merged["space:2"]?.value == nil)
}

@Test func joiningDeviceKeepsExistingFolderValueAndAddsItsUniqueValues() {
    let peer: [String: BrowserSyncEntry] = [
        "space:1": .init(value: "shared", timestamp: 8, deviceID: "A"),
        "space:2": .init(value: "remote", timestamp: 8, deviceID: "A"),
    ]
    let merged = BrowserSyncMerge.pass(current: ["space:1": "local", "space:3": "local only"],
                                       base: nil, peers: [peer], deviceID: "Z", now: 50)
    #expect(BrowserSyncMerge.live(merged)["space:1"] == "shared")
    #expect(BrowserSyncMerge.live(merged)["space:2"] == "remote")
    #expect(BrowserSyncMerge.live(merged)["space:3"] == "local only")
}

@Test func emptyCollectionLossCanBeProtectedFromMassDeletion() {
    let base = Dictionary(uniqueKeysWithValues: (0..<5).map { index in
        ("space:\(index)", BrowserSyncEntry(value: "present", timestamp: 1, deviceID: "A"))
    })
    let stamped = BrowserSyncMerge.stamp(current: [:], base: base, deviceID: "A", now: 2,
                                         protectedPrefixes: ["space:"])
    #expect(stamped.values.allSatisfy { $0.value != nil })
}

@Test func syncFileRoundTripsAndRejectsWrongScope() throws {
    let file = BrowserSyncFile(deviceID: "device", deviceName: "Mac", scope: "app", writtenAt: 12,
                               entries: ["setting:theme": .init(value: "dark", timestamp: 11, deviceID: "device")])
    let data = try #require(BrowserSyncMerge.encode(file))
    #expect(BrowserSyncMerge.decode(data, scope: "app") == file)
    #expect(BrowserSyncMerge.decode(data, scope: "profile-other") == nil)
    #expect(BrowserSyncMerge.decode(Data("[]".utf8), scope: "app") == nil)
}

@Test func canonicalSyncTextIgnoresDictionaryInsertionOrder() {
    let left = ["b": 2, "a": 1]
    let right = ["a": 1, "b": 2]
    #expect(BrowserSyncMerge.text(left) == BrowserSyncMerge.text(right))
}

@Test func folderTransportMergesDevicesWithoutReplacingPeerFiles() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "ark-sync-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let mac = UUID()
    let phone = UUID()
    let first = try BrowserSyncFolderTransport.synchronize(
        in: root, scope: "browser", deviceID: mac, deviceName: "Mac",
        current: ["space:one": "mac", "space:two": "shared"],
        now: Date(timeIntervalSince1970: 10)
    )
    #expect(first == ["space:one": "mac", "space:two": "shared"])

    let joined = try BrowserSyncFolderTransport.synchronize(
        in: root, scope: "browser", deviceID: phone, deviceName: "iPhone",
        current: ["space:one": "phone", "space:three": "phone-only"],
        now: Date(timeIntervalSince1970: 5)
    )
    #expect(joined == ["space:one": "mac", "space:two": "shared", "space:three": "phone-only"])

    let syncedBack = try BrowserSyncFolderTransport.synchronize(
        in: root, scope: "browser", deviceID: mac, deviceName: "Mac",
        current: ["space:one": "mac", "space:two": "shared"],
        now: Date(timeIntervalSince1970: 11)
    )
    #expect(syncedBack == joined)
    let files = try FileManager.default.contentsOfDirectory(atPath: root.path)
    #expect(files.count == 2)
}

@Test func folderTransportRejectsAnInvalidScopeWithoutCreatingFiles() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "ark-sync-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    #expect(throws: BrowserSyncFolderTransport.TransportError.invalidScope) {
        try BrowserSyncFolderTransport.synchronize(
            in: root, scope: "../other", deviceID: UUID(), current: [:]
        )
    }
    let files = try FileManager.default.contentsOfDirectory(atPath: root.path)
    #expect(files.isEmpty)
}

@Test @MainActor func syncCoordinatorPersistsFolderAccessAndRunsAMerge() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "ark-sync-config-\(UUID().uuidString)")
    let sharedFolder = root.appending(path: "shared")
    let configurationURL = root.appending(path: "settings/sync.json")
    try FileManager.default.createDirectory(at: sharedFolder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let coordinator = BrowserSyncCoordinator(configurationURL: configurationURL)
    try coordinator.selectFolder(sharedFolder)
    #expect(coordinator.isConfigured)
    #expect(coordinator.folderName == "shared")

    let snapshot = BrowserSnapshot(spaces: [], selectedSpaceID: nil, favorites: [], archive: [], settings: nil, saved: nil)
    let merged = await coordinator.synchronize(snapshot)
    #expect(merged?.spaces.isEmpty == true)

    let restored = BrowserSyncCoordinator(configurationURL: configurationURL)
    #expect(restored.isConfigured)
    #expect(restored.folderName == "shared")
}
