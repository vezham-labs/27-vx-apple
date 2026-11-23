import SwiftUI

public struct PinFolderList<TabRow: View>: View {
    private let space: Space
    private let save: () -> Void
    private let dropTarget: UUID?
    private let folderLayout: ((UUID, CGRect?) -> Void)?
    private let coordinateSpace: String?
    private let openArticle: ((URL) -> Void)?
    private let allowsCollectionSharing: Bool
    private let tabRow: (BrowserTab) -> TabRow
    @State private var parentID: UUID?
    @State private var renameID: UUID?
    @State private var folderName = ""
    @State private var editing = false
    @State private var addingFeed = false
    @State private var loadingFeed = false
    @State private var feedAddress = ""
    @State private var feedError: String?

    public init(
        space: Space, save: @escaping () -> Void,
        dropTarget: UUID? = nil, coordinateSpace: String? = nil,
        folderLayout: ((UUID, CGRect?) -> Void)? = nil,
        openArticle: ((URL) -> Void)? = nil,
        allowsCollectionSharing: Bool = true,
        @ViewBuilder tabRow: @escaping (BrowserTab) -> TabRow
    ) {
        self.space = space
        self.save = save
        self.dropTarget = dropTarget
        self.coordinateSpace = coordinateSpace
        self.folderLayout = folderLayout
        self.openArticle = openArticle
        self.allowsCollectionSharing = allowsCollectionSharing
        self.tabRow = tabRow
    }

    private enum Row: Identifiable {
        case folder(PinFolder, depth: Int)
        case tab(BrowserTab, depth: Int)
        case article(UUID, LiveFolderFeed.Article, depth: Int)

        var id: String {
            switch self {
            case .folder(let folder, _): "folder-\(folder.id)"
            case .tab(let tab, _): "tab-\(tab.id)"
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
                    for tab in pins[folder.id] ?? [] { result.append(.tab(tab, depth: depth + 1)) }
                    if openArticle != nil, let feed = folder.feed {
                        for article in feed.articles { result.append(.article(folder.id, article, depth: depth + 1)) }
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
                    case .tab(let tab, let depth):
                        tabRow(tab).padding(.leading, CGFloat(depth) * 12)
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
                    for folder in space.pinFolders where folder.feed != nil {
                        guard !Task.isCancelled else { return }
                        if (try? await space.refreshLiveFolder(folder.id, minimumAge: refreshInterval, allowActivation: false)) == true { save() }
                    }
                    try? await Task.sleep(for: .seconds(refreshInterval))
                }
            }
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
                if dropTarget == folder.id {
                    RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.23))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityValue(folder.isCollapsed ? "Collapsed" : "Expanded")
        .contextMenu {
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
                Button(folder.feedNeedsActivation == true ? "Resume Feed" : "Refresh Feed", systemImage: "arrow.clockwise") {
                    Task {
                        do {
                            if try await space.refreshLiveFolder(folder.id) { save() }
                        } catch {
                            feedError = error.localizedDescription
                        }
                    }
                }
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
        if tab.isPinned, !space.pinFolders.isEmpty {
            Menu("Move to Folder", systemImage: "folder") {
                Button("Top Level") { move(to: nil) }.disabled(tab.pinFolderID == nil)
                ForEach(space.pinFolders) { folder in
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
