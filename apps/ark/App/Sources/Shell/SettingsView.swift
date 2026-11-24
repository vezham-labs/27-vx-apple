import SwiftUI
import BrowserCore
import Suggest
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(BrowserState.self) private var browser
    @Environment(\.dismiss) private var dismiss
    @State private var braveKey = ""
    @State private var confirmClearHistory = false
    @State private var confirmClearWebsiteData = false
    @State private var exportDocument: ArkSpaceLinkDocument?
    @State private var isExportingSpace = false
    @State private var isImportingSpace = false
    @State private var isChoosingSyncFolder = false
    @State private var spaceFileMessage: String?

    private func groupBinding(_ group: FilterGroup) -> Binding<Bool> {
        Binding {
            browser.settings.filterGroups.contains(group)
        } set: { on in
            if on { browser.settings.filterGroups.insert(group) } else { browser.settings.filterGroups.remove(group) }
        }
    }

    @ViewBuilder private var filterStatusRow: some View {
        let status = browser.filterStatus
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                if status.isUpdating {
                    Text("Updating filters…")
                } else if let last = status.lastUpdated {
                    Text("\(status.ruleCount.formatted()) rules")
                    Text("Updated \(last.formatted(.relative(presentation: .named)))")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Using the built-in starter list")
                    if ContentBlocker.rulesBaseURL != nil {
                        Text("Full filters download on Wi-Fi or cellular in the background.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let error = status.error {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            Spacer()
            if status.isUpdating {
                ProgressView()
            } else if ContentBlocker.rulesBaseURL != nil {
                Button("Update") { Task { await browser.updateFilters() } }
                    .buttonStyle(.borderless)
            }
        }
    }

    private enum EngineChoice: String, CaseIterable, Identifiable {
        case google = "Google", duckDuckGo = "DuckDuckGo", brave = "Brave"
        var id: String { rawValue }
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        @Bindable var browser = browser
        NavigationStack {
            Form {
                Section {
                    Picker("Search engine", selection: engineBinding) {
                        ForEach(EngineChoice.allCases) { Text($0.rawValue).tag($0) }
                    }
                    if case .brave = browser.settings.searchEngine {
                        SecureField("Brave Search API key", text: $braveKey)
                            .onSubmit { browser.settings.searchEngine = .brave(apiKey: braveKey) }
                    }
                    Toggle("Search suggestions", isOn: $browser.settings.remoteSuggestions)
                } header: {
                    Text("Search")
                } footer: {
                    Text("Outside private tabs, search suggestions send what you type to \(SuggestEngine.defaultSources(for: browser.settings.searchEngine).map(\.displayName).formatted(.list(type: .and))). Favourites, history, open tabs and the built-in list of popular sites are always matched on the device.")
                }

                Section {
                    Toggle("Desktop sites when unfolded", isOn: $browser.settings.desktopSitesWhenUnfolded)
                    NavigationLink("Website settings") { WebsiteSettingsView() }
                } header: {
                    Text("Websites")
                } footer: {
                    Text("On the inner display, pages ask for the desktop version like iPad Safari. Folded, they get the mobile version. Changes apply to pages you open next.")
                }

                Section("Tabs") {
                    Picker("Archive today tabs after", selection: $browser.settings.archiveAfterHours) {
                        Text("6 hours").tag(6.0)
                        Text("12 hours").tag(12.0)
                        Text("1 day").tag(24.0)
                        Text("7 days").tag(168.0)
                        Text("Never").tag(Double.greatestFiniteMagnitude)
                    }
                    Picker("Links from other apps open in", selection: $browser.settings.externalLinksSpaceID) {
                        Text("Current space").tag(UUID?.none)
                        ForEach(browser.regularSpaces) { s in Text(s.name).tag(Optional(s.id)) }
                    }
                    NavigationLink("Space Routing") { SpaceRoutingSettings() }
                }

                Section {
                    Toggle("Block ads and trackers", isOn: $browser.settings.blockContent)
                    if browser.settings.blockContent {
                        ForEach(FilterGroup.allCases) { group in
                            Toggle(isOn: groupBinding(group)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(group.title)
                                    Text(group.detail).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        filterStatusRow
                    }
                    Toggle("Decline cookie banners", isOn: $browser.settings.declineCookieBanners)
                    Toggle("Remove tracking from links", isOn: $browser.settings.cleanLinks)
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("Uses AdGuard's filter lists, refreshed every few days, and DuckDuckGo's cookie-banner engine, which picks \"reject\" for you. Removing tracking strips tags like utm_source and fbclid from links you open and copy. Switch everything off for one site from its page menu.")
                }

                Section("Spaces") {
                    ForEach(browser.regularSpaces) { space in
                        SpaceEditorRow(space: space)
                    }
                    Button("Add Space", systemImage: "plus") { browser.addSpace() }
                    Button("Import Space Links…", systemImage: "square.and.arrow.down") { isImportingSpace = true }
                    Menu("Share Space Links…", systemImage: "square.and.arrow.up") {
                        ForEach(browser.regularSpaces) { space in
                            if let archive = SpaceLinkArchive(space: space) {
                                ShareLink(item: archive, preview: SharePreview(space.name)) { Text("Share \(space.name)") }
                            }
                        }
                    }
                    Menu {
                        ForEach(browser.regularSpaces) { space in
                            Button("Export \(space.name)") { exportSpaceLinks(space) }
                        }
                    } label: {
                        Label("Export Space Links…", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                }

                Section {
                    LabeledContent("Folder", value: browser.syncCoordinator.folderName ?? "Not configured")
                    LabeledContent("Status", value: syncStatus)
                    if let lastSyncedAt = browser.syncCoordinator.lastSyncedAt {
                        LabeledContent("Last synced", value: lastSyncedAt.formatted(.relative(presentation: .named)))
                    }
                    Button("Choose Shared Folder…", systemImage: "folder") { isChoosingSyncFolder = true }
                    Button("Sync Now", systemImage: "arrow.triangle.2.circlepath") {
                        Task { await browser.syncNow() }
                    }
                    .disabled(!browser.syncCoordinator.isConfigured || isSyncing)
                    if browser.syncCoordinator.isConfigured {
                        Button("Disconnect", role: .destructive) { browser.syncCoordinator.disconnect() }
                    }
                } header: {
                    Text("Sync")
                } footer: {
                    Text("Choose the same shared folder on each device. Ark syncs Spaces, pinned links, favourites and selected settings. Today tabs and history stay on this device.")
                }

                Section {
                    Button("Clear History", role: .destructive) { confirmClearHistory = true }
                    Button("Clear Cookies and Site Data", role: .destructive) { confirmClearWebsiteData = true }
                } footer: {
                    Text("Clearing cookies and site data signs you out of websites.")
                }

                Section("About") {
                    Link("Ark Website", destination: URL(string: "https://ark.vezham.com")!)
                    LabeledContent("Version", value: Self.version)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .confirmationDialog("Clear all browsing history?", isPresented: $confirmClearHistory, titleVisibility: .visible) {
                Button("Clear History", role: .destructive) { Task { await browser.clearHistory() } }
            }
            .confirmationDialog("Clear all cookies and site data?", isPresented: $confirmClearWebsiteData, titleVisibility: .visible) {
                Button("Clear Cookies and Site Data", role: .destructive) { Task { await browser.clearWebsiteData() } }
            } message: {
                Text("This signs you out of websites. Your tabs, history and favourites stay.")
            }
            .onAppear {
                if case .brave(let key) = browser.settings.searchEngine { braveKey = key }
            }
            .fileImporter(isPresented: $isImportingSpace, allowedContentTypes: [.json], onCompletion: importSpaceLinks)
            .fileImporter(isPresented: $isChoosingSyncFolder, allowedContentTypes: [.folder]) { result in
                if case .failure(let error) = result, error is CancellationError { return }
                do {
                    try browser.syncCoordinator.selectFolder(result.get())
                    Task { await browser.syncNow() }
                } catch {
                    spaceFileMessage = error.localizedDescription
                }
            }
            .fileExporter(isPresented: $isExportingSpace, document: exportDocument, contentType: .json,
                          defaultFilename: "Ark Space") { result in
                if case .failure = result { spaceFileMessage = "Couldn’t export Space links." }
                exportDocument = nil
            }
            .alert("Space Links", isPresented: Binding(get: { spaceFileMessage != nil },
                                                        set: { if !$0 { spaceFileMessage = nil } })) {
                Button("OK", role: .cancel) { spaceFileMessage = nil }
            } message: {
                Text(spaceFileMessage ?? "")
            }
        }
    }

    private var isSyncing: Bool {
        if case .syncing = browser.syncCoordinator.state { return true }
        return false
    }

    private var syncStatus: String {
        switch browser.syncCoordinator.state {
        case .off: "Off"
        case .ready: "Ready"
        case .syncing: "Syncing…"
        case .synced: "Synced"
        case .failed(let message): message
        }
    }

    private func exportSpaceLinks(_ space: Space) {
        guard let archive = SpaceLinkArchive(space: space) else { return }
        do {
            exportDocument = ArkSpaceLinkDocument(data: try archive.encoded())
            isExportingSpace = true
        } catch {
            spaceFileMessage = error.localizedDescription
        }
    }

    private func importSpaceLinks(_ result: Result<URL, any Error>) {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let archive = try SpaceLinkArchive(contentsOf: url)
            let space = browser.importSpaceLinks(archive)
            spaceFileMessage = "Imported \(space.name)."
        } catch let error as SpaceLinkArchive.InvalidArchive {
            spaceFileMessage = error.localizedDescription
        } catch {
            spaceFileMessage = "Couldn’t read the Ark Space file."
        }
    }

    private var engineBinding: Binding<EngineChoice> {
        Binding {
            switch browser.settings.searchEngine {
            case .google: .google
            case .duckDuckGo: .duckDuckGo
            case .brave: .brave
            }
        } set: { choice in
            switch choice {
            case .google: browser.settings.searchEngine = .google
            case .duckDuckGo: browser.settings.searchEngine = .duckDuckGo
            case .brave: browser.settings.searchEngine = .brave(apiKey: braveKey)
            }
        }
    }
}

private struct ArkSpaceLinkDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private struct SpaceEditorRow: View {
    @Environment(BrowserState.self) private var browser
    @Bindable var space: Space
    @State private var profileName = ""
    @State private var creatingProfile = false
    @State private var editingProfileID: UUID?
    @State private var deletingProfileID: UUID?
    @State private var confirmingProfileDeletion = false

    private let symbols = ["house.fill", "briefcase.fill", "book.fill", "gamecontroller.fill",
                           "cart.fill", "airplane", "paintpalette.fill", "hammer.fill"]

    var body: some View {
        HStack {
            Menu {
                ForEach(symbols, id: \.self) { sym in
                    Button(sym, systemImage: sym) { space.symbol = sym; browser.scheduleSave() }
                }
            } label: {
                Image(systemName: space.symbol)
                    .foregroundStyle(SpacePalette.color(space.colorIndex))
                    .frame(width: 28)
            }
            TextField("Name", text: $space.name)
                .onSubmit { browser.scheduleSave() }
            Menu {
                ForEach(SpacePalette.colors.indices, id: \.self) { i in
                    Button { space.colorIndex = i; browser.scheduleSave() } label: {
                        Label("Colour \(i + 1)", systemImage: "circle.fill")
                    }
                    .tint(SpacePalette.color(i))
                }
            } label: {
                Circle().fill(SpacePalette.color(space.colorIndex)).frame(width: 18, height: 18)
            }
            profileMenu
        }
        .alert(editingProfileID == nil ? "New Website Profile" : "Rename Website Profile", isPresented: $creatingProfile) {
            TextField("Profile Name", text: $profileName)
            Button("Cancel", role: .cancel) { editingProfileID = nil }
            Button(editingProfileID == nil ? "Create" : "Save") {
                if let id = editingProfileID {
                    browser.renameWebsiteProfile(id, to: profileName)
                    editingProfileID = nil
                } else {
                    guard let profile = WebsiteProfile(name: profileName) else { return }
                    browser.settings.websiteProfiles.append(profile)
                    browser.assignWebsiteProfile(profile.id, to: space)
                }
            }
            .disabled(profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("A profile keeps website sign-ins and storage separate. Changing profiles reloads the Space’s tabs.")
        }
        .confirmationDialog("Delete Website Profile?", isPresented: $confirmingProfileDeletion, titleVisibility: .visible) {
            Button("Delete Profile", role: .destructive) {
                guard let id = deletingProfileID else { return }
                Task { await browser.deleteWebsiteProfile(id) }
                deletingProfileID = nil
            }
            Button("Cancel", role: .cancel) { deletingProfileID = nil }
        } message: {
            Text("Spaces using this profile return to Default. Its sign-ins, site data, history, and favorites will be deleted from this device.")
        }
        .swipeActions {
            if browser.regularSpaces.count > 1 {
                Button("Delete", role: .destructive) { browser.deleteSpace(space) }
            }
        }
    }

    private var profileMenu: some View {
        let selected = browser.settings.websiteProfiles.first { $0.id == space.websiteProfileID }
        return Menu {
            Picker("Website Profile", selection: Binding(
                get: { space.websiteProfileID },
                set: { browser.assignWebsiteProfile($0, to: space) }
            )) {
                Text("Default Profile").tag(UUID?.none)
                ForEach(browser.settings.websiteProfiles) { profile in
                    Text(profile.name).tag(Optional(profile.id))
                }
            }
            Divider()
            Button("New Website Profile…") {
                profileName = ""
                editingProfileID = nil
                creatingProfile = true
            }
            if let selected {
                Button("Rename \(selected.name)…") {
                    profileName = selected.name
                    editingProfileID = selected.id
                    creatingProfile = true
                }
                Button("Delete \(selected.name)…", role: .destructive) {
                    deletingProfileID = selected.id
                    confirmingProfileDeletion = true
                }
            }
        } label: {
            Image(systemName: "person.crop.circle")
                .foregroundStyle(space.websiteProfileID == nil ? Color.secondary : Color.primary)
        }
        .accessibilityLabel("Website Profile for \(space.name)")
        .accessibilityValue(selected?.name ?? "Default")
    }
}

/// Every site with a remembered permission or a desktop/mobile choice. Swipe to forget.
struct WebsiteSettingsView: View {
    @Environment(BrowserState.self) private var browser

    private var hosts: [String] {
        Set(browser.settings.sitePermissions.keys).union(browser.settings.siteDesktopOverrides.keys)
            .union(browser.settings.blockingDisabledHosts).sorted()
    }

    var body: some View {
        List {
            if hosts.isEmpty {
                ContentUnavailableView("No website settings", systemImage: "globe",
                                       description: Text("Permissions you grant, sites you switch to desktop or mobile, and sites with blockers off show up here."))
            }
            ForEach(hosts, id: \.self) { host in
                VStack(alignment: .leading, spacing: 4) {
                    Text(host).font(.body.weight(.medium))
                    Text(summary(for: host)).font(.caption).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            .onDelete { idx in
                for host in idx.map({ hosts[$0] }) {
                    browser.forgetPermissions(for: host)
                    browser.settings.siteDesktopOverrides[host] = nil
                    browser.settings.blockingDisabledHosts.remove(host)
                }
            }
        }
        .navigationTitle("Website Settings")
        .toolbar { EditButton() }
    }

    private func summary(for host: String) -> String {
        var parts: [String] = []
        if let d = browser.settings.siteDesktopOverrides[host] { parts.append(d ? "Desktop site" : "Mobile site") }
        if browser.settings.blockingDisabledHosts.contains(host) { parts.append("Blockers off") }
        for (perm, allowed) in (browser.settings.sitePermissions[host] ?? [:]).sorted(by: { $0.key < $1.key }) {
            let name = SitePermission(rawValue: perm).map { p in
                switch p {
                case .camera: "Camera"
                case .microphone: "Microphone"
                case .cameraAndMicrophone: "Camera and microphone"
                case .motion: "Motion"
                }
            } ?? perm
            parts.append("\(name): \(allowed ? "Allow" : "Deny")")
        }
        return parts.joined(separator: " · ")
    }
}
