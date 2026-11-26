import SwiftUI

public enum PinFolderDragItem {
    public static func pin(_ id: UUID) -> String { "pin:\(id.uuidString)" }
    public static func folder(_ id: UUID) -> String { "folder:\(id.uuidString)" }

    public static func pinID(_ value: String) -> UUID? {
        guard value.hasPrefix("pin:") else { return nil }
        return UUID(uuidString: String(value.dropFirst(4)))
    }

    public static func folderID(_ value: String) -> UUID? {
        guard value.hasPrefix("folder:") else { return nil }
        return UUID(uuidString: String(value.dropFirst(7)))
    }
}

public struct PinFolderList<TabRow: View>: View {
    private let space: Space
    private let save: () -> Void
    private let dropTarget: UUID?
    private let folderLayout: ((UUID, CGRect?) -> Void)?
    private let coordinateSpace: String?
    private let openArticle: ((URL) -> Void)?
    private let openAllFolderTabs: ((PinFolder) -> Void)?
    private let refreshGitHub: ((UUID) async throws -> Void)?
    private let moveTodayTab: ((UUID, UUID?, UUID?, Bool) -> Bool)?
    private let allowsCollectionSharing: Bool
    private let tabRow: (BrowserTab, Int) -> TabRow
    @State private var parentID: UUID?
    @State private var renameID: UUID?
    @State private var folderName = ""
    @State private var editing = false
    @State private var addingFeed = false
    @State private var loadingFeed = false
    @State private var feedAddress = ""
    @State private var feedError: String?
    @State private var folderDropTarget: UUID?
    @State private var pinDropTarget: UUID?
    @State private var folderRowHeights: [UUID: CGFloat] = [:]
    @State private var pinRowHeights: [UUID: CGFloat] = [:]

    public init(
        space: Space, save: @escaping () -> Void,
        dropTarget: UUID? = nil, coordinateSpace: String? = nil,
        folderLayout: ((UUID, CGRect?) -> Void)? = nil,
        openArticle: ((URL) -> Void)? = nil,
        openAllFolderTabs: ((PinFolder) -> Void)? = nil,
        refreshGitHub: ((UUID) async throws -> Void)? = nil,
        moveTodayTab: ((UUID, UUID?, UUID?, Bool) -> Bool)? = nil,
        allowsCollectionSharing: Bool = true,
        @ViewBuilder tabRow: @escaping (BrowserTab, Int) -> TabRow
    ) {
        self.space = space
        self.save = save
        self.dropTarget = dropTarget
        self.coordinateSpace = coordinateSpace
        self.folderLayout = folderLayout
        self.openArticle = openArticle
        self.openAllFolderTabs = openAllFolderTabs
        self.refreshGitHub = refreshGitHub
        self.moveTodayTab = moveTodayTab
        self.allowsCollectionSharing = allowsCollectionSharing
        self.tabRow = tabRow
    }

    private enum Row: Identifiable {
        case folder(PinFolder, depth: Int)
        case tab(BrowserTab, depth: Int, paneCount: Int)
        case article(UUID, LiveFolderFeed.Article, depth: Int)

        var id: String {
            switch self {
            case .folder(let folder, _): "folder-\(folder.id)"
            case .tab(let tab, _, _): "tab-\(tab.id)"
            case .article(let folderID, let article, _): "article-\(folderID)-\(article.id)"
            }
        }
    }

    private var rows: [Row] {
        guard !space.pinFolders.isEmpty else { return [] }
        let children = Dictionary(grouping: space.pinFolders, by: \.parentID)
        let pins = Dictionary(grouping: space.pinned, by: \.pinFolderID)
        var result: [Row] = []
        func addChildren(of parent: UUID?, depth: Int) {
            for folder in children[parent] ?? [] {
                result.append(.folder(folder, depth: depth))
                if !folder.isCollapsed {
                    addChildren(of: folder.id, depth: depth + 1)
                    let folderPins = pins[folder.id] ?? []
                    let splitMembers = space.splitMembers(in: folderPins)
                    for tab in space.sidebarRowsCollapsingSplit(folderPins) {
                        let paneCount = splitMembers?.contains(where: { $0.id == tab.id }) == true ? (splitMembers?.count ?? 1) : 1
                        result.append(.tab(tab, depth: depth + 1, paneCount: paneCount))
                    }
                    if openArticle != nil, folder.feed != nil {
                        for article in folder.visibleArticles { result.append(.article(folder.id, article, depth: depth + 1)) }
                    }
                }
            }
        }
        addChildren(of: nil, depth: 0)
        return result
    }

    public var body: some View {
        if !space.isPrivate {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(rows) { row in
                    switch row {
                    case .folder(let folder, let depth):
                        measuredFolderRow(folder).padding(.leading, CGFloat(depth) * 12)
                    case .tab(let tab, let depth, let paneCount):
                        pinnedTabRow(tab, depth: depth, paneCount: paneCount)
                    case .article(_, let article, let depth):
                        Button { openArticle?(article.url) } label: {
                            Label(article.title, systemImage: "doc.text")
                                .lineLimit(1)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .font(.callout)
                        .padding(.leading, CGFloat(depth) * 12)
                    }
                }
                Button { edit() } label: {
                    Label("New Pin Folder", systemImage: "folder.badge.plus")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.plain)
                .dropDestination(for: String.self) { items, _ in
                    guard let value = items.first else { return false }
                    if let pinID = PinFolderDragItem.pinID(value) {
                        guard space.movePinnedTab(pinID, into: nil) else { return false }
                    } else {
                        if let folderID = PinFolderDragItem.folderID(value) {
                            guard space.movePinFolder(folderID, into: nil) else { return false }
                        } else if let tabID = UUID(uuidString: value),
                                  moveTodayTab?(tabID, nil, nil, false) == true {
                            // A Today tab joined the top-level pinned rows.
                        } else {
                            return false
                        }
                    }
                    save()
                    return true
                }
                if openArticle != nil {
                    Button { editFeed() } label: {
                        Label(loadingFeed ? "Adding Live Folder…" : "New Live Folder", systemImage: "dot.radiowaves.left.and.right")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                    }
                    .buttonStyle(.plain)
                    .disabled(loadingFeed)
                }
            }
            .alert(renameID == nil ? "New Pin Folder" : "Rename Pin Folder", isPresented: $editing) {
                TextField("Folder Name", text: $folderName)
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    if let renameID {
                        space.renamePinFolder(renameID, to: folderName)
                    } else {
                        space.addPinFolder(named: folderName, inside: parentID)
                    }
                    save()
                }
                .disabled(folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .alert("New Live Folder", isPresented: $addingFeed) {
                TextField("Feed or Website Address", text: $feedAddress)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
                Button("Cancel", role: .cancel) {}
                Button("Add") { addFeed() }
                    .disabled(feedAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } message: {
                Text("Enter an RSS or Atom feed address, or a website that links to one.")
            }
            .alert("Live Folder", isPresented: Binding(
                get: { feedError != nil },
                set: { if !$0 { feedError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(feedError ?? "")
            }
            .task(id: space.id) {
                guard openArticle != nil else { return }
                let refreshInterval: TimeInterval = 900
                while !Task.isCancelled {
                    for folder in space.pinFolders where folder.feed != nil && folder.feed?.isGitHubPullRequests != true {
                        guard !Task.isCancelled else { return }
                        if (try? await space.refreshLiveFolder(folder.id, minimumAge: refreshInterval, allowActivation: false)) == true { save() }
                    }
                    try? await Task.sleep(for: .seconds(refreshInterval))
                }
            }
        }
    }

    @ViewBuilder private func pinnedTabRow(_ tab: BrowserTab, depth: Int, paneCount: Int) -> some View {
        let isDropTarget = pinDropTarget == tab.id
        let row = tabRow(tab, paneCount)
            .padding(.leading, CGFloat(depth) * 12)
            .background {
                if isDropTarget {
                    RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.18))
                }
            }
        row
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { pinRowHeights[tab.id] = $0 }
            .draggable(PinFolderDragItem.pin(tab.id)) { tabRow(tab, paneCount) }
            .dropDestination(for: String.self) { items, location in
                guard let value = items.first else { return false }
                if let folderID = PinFolderDragItem.folderID(value) {
                    guard space.movePinFolder(folderID, into: tab.pinFolderID) else { return false }
                } else if let pinID = PinFolderDragItem.pinID(value) {
                    guard space.movePinnedTab(pinID, into: tab.pinFolderID, relativeTo: tab.id,
                                              after: location.y >= (pinRowHeights[tab.id] ?? 44) / 2) else { return false }
                } else if let todayID = UUID(uuidString: value),
                          moveTodayTab?(todayID, tab.pinFolderID, tab.id,
                                        location.y >= (pinRowHeights[tab.id] ?? 44) / 2) == true {
                    // The dragged Today tab was inserted beside this pin.
                } else {
                    return false
                }
                save()
                return true
            } isTargeted: { targeted in
                if targeted { pinDropTarget = tab.id }
                else if pinDropTarget == tab.id { pinDropTarget = nil }
            }
    }

    @ViewBuilder private func measuredFolderRow(_ folder: PinFolder) -> some View {
        if let coordinateSpace, let folderLayout {
            folderRow(folder)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(coordinateSpace)) } action: {
                    folderLayout(folder.id, $0)
                }
                .onDisappear { folderLayout(folder.id, nil) }
        } else {
            folderRow(folder)
        }
    }

    private func folderRow(_ folder: PinFolder) -> some View {
        Button {
            space.togglePinFolder(folder.id)
            save()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: folder.isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.caption2)
                    .frame(width: 10)
                Label(folder.name, systemImage: folder.feed != nil ? "dot.radiowaves.left.and.right" : folder.isCollapsed ? "folder" : "folder.fill")
                    .lineLimit(1)
                Spacer()
            }
            .font(.callout)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background {
                if dropTarget == folder.id || folderDropTarget == folder.id {
                    RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.23))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityValue(folder.isCollapsed ? "Collapsed" : "Expanded")
        .accessibilityHint("Drag above or below another folder to reorder, or to the center of a folder to nest.")
        .draggable(PinFolderDragItem.folder(folder.id)) {
            Label(folder.name, systemImage: "folder")
                .padding(10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
        .dropDestination(for: String.self, action: { items, location in
            guard let value = items.first else { return false }
            let moved: Bool
            if let pinID = PinFolderDragItem.pinID(value) {
                moved = space.movePinnedTab(pinID, into: folder.id)
            } else if let id = PinFolderDragItem.folderID(value) {
                let fraction = location.y / max(folderRowHeights[folder.id] ?? 32, 1)
                moved = space.movePinFolder(id, relativeTo: folder.id, verticalFraction: fraction)
            } else if let todayID = UUID(uuidString: value) {
                moved = moveTodayTab?(todayID, folder.id, nil, false) ?? false
            } else {
                moved = false
            }
            if moved { save() }
            return moved
        }, isTargeted: { targeted in
                if targeted { folderDropTarget = folder.id }
                else if folderDropTarget == folder.id { folderDropTarget = nil }
            }
        )
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            if folderRowHeights[folder.id] != height { folderRowHeights[folder.id] = height }
        }
        .contextMenu {
            if folder.feed == nil, let openAllFolderTabs {
                Button("Open All Tabs in Folder", systemImage: "square.stack") { openAllFolderTabs(folder) }
            }
            Button("Rename Folder…", systemImage: "pencil") { edit(folder) }
            if allowsCollectionSharing, let archive = SpaceLinkArchive(space: space, folderID: folder.id) {
                ShareLink(item: archive, preview: SharePreview(archive.name)) {
                    Label("Share Folder Links…", systemImage: "square.and.arrow.up")
                }
            }
            if space.canNestPinFolder(in: folder.id) {
                Button("New Subfolder…", systemImage: "folder.badge.plus") { edit(inside: folder.id) }
                if openArticle != nil {
                    Button("New Live Subfolder…", systemImage: "dot.radiowaves.left.and.right") { editFeed(inside: folder.id) }
                        .disabled(loadingFeed)
                }
            }
            if folder.feed != nil {
                if !folder.githubOwners.isEmpty {
                    Menu("Organizations") {
                        ForEach(folder.githubOwners, id: \.self) { owner in
                            Toggle(owner, isOn: Binding(
                                get: { space.pinFolders.first(where: { $0.id == folder.id })?.showsGitHubOwner(owner) ?? true },
                                set: { space.setGitHubOwner(owner, shown: $0, in: folder.id); save() }
                            ))
                        }
                    }
                }
                Button(folder.feedNeedsActivation == true ? "Resume Feed" : "Refresh Feed", systemImage: "arrow.clockwise") {
                    Task {
                        do {
                            if folder.feed?.isGitHubPullRequests == true {
                                guard let refreshGitHub else { return }
                                try await refreshGitHub(folder.id)
                            } else if try await space.refreshLiveFolder(folder.id) { save() }
                        } catch {
                            feedError = error.localizedDescription
                        }
                    }
                }
                .disabled(folder.feed?.isGitHubPullRequests == true && refreshGitHub == nil)
            }
            Button("Remove Folder", systemImage: "folder.badge.minus") {
                space.removePinFolder(folder.id)
                save()
            }
        }
    }

    private func edit(_ folder: PinFolder? = nil, inside parent: UUID? = nil) {
        renameID = folder?.id
        parentID = parent
        folderName = folder?.name ?? ""
        editing = true
    }

    private func editFeed(inside parent: UUID? = nil) {
        parentID = parent
        feedAddress = ""
        addingFeed = true
    }

    private func addFeed() {
        let address = feedAddress
        let parent = parentID
        loadingFeed = true
        Task {
            defer { loadingFeed = false }
            do {
                if try await space.addLiveFolder(address: address, inside: parent) != nil { save() }
            } catch {
                feedError = error.localizedDescription
            }
        }
    }
}

public struct MovePinMenu: View {
    let tab: BrowserTab
    let space: Space
    let save: () -> Void

    public init(tab: BrowserTab, space: Space, save: @escaping () -> Void) {
        self.tab = tab
        self.space = space
        self.save = save
    }

    public var body: some View {
        if tab.isPinned, space.pinFolders.contains(where: { $0.feed == nil }) {
            Menu("Move to Folder", systemImage: "folder") {
                Button("Top Level") { move(to: nil) }.disabled(tab.pinFolderID == nil)
                ForEach(space.pinFolders.filter { $0.feed == nil }) { folder in
                    Button(space.pinFolderName(folder)) { move(to: folder.id) }
                        .disabled(tab.pinFolderID == folder.id)
                }
            }
        }
    }

    private func move(to folderID: UUID?) {
        space.setPinFolder(folderID, for: tab)
        save()
    }
}
