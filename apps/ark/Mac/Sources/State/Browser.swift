import AppKit
import Observation
import BrowserCore
import BrowserEngine
import WebKitEngine
import Suggest
import SwiftUI

/// One Ark window: which space and tab it shows, and the transient UI around them.
/// Spaces, tabs, favourites and settings live in the shared `Library`.
@MainActor @Observable
final class Browser {
    let library: Library
    /// Stable for the window's life, for extensions.
    let id = UUID()
    /// Names the window across launches (SwiftUI restores it with the window), so each window
    /// gets its own Today tabs back. Saved on those tabs as `BrowserTab.windowKey`.
    let windowKey: UUID
    /// Opened just now rather than restored from the last launch, so it takes its size from the
    /// window in use (see `WindowSizing`).
    let isNewWindow: Bool
    var selectedSpaceID: UUID
    /// Pins selected with Command-click or Shift-click in the Mac sidebar.
    var selectedSidebarPinIDs: Set<UUID> = []
    @ObservationIgnored private var sidebarPinSelectionAnchor: UUID?
    var isCreatingPinFolderForSelection = false
    var newPinFolderName = ""
    @ObservationIgnored private var pendingPinFolderIDs: Set<UUID> = []
    @ObservationIgnored private var pendingPinFolderSpaceID: UUID?
    @ObservationIgnored private var pinMoveUndo: PinMoveUndo?
    /// The tab this window shows in each space it has visited. Two windows never show the same tab.
    private var tabSelection: [UUID: UUID] = [:]
    private var lastUsedTabIDs: [UUID: UUID] = [:]
    var splitBySpace: [UUID: TabSplit]
    var isSplitPickerPresented = false
    var isRecentTabsPresented = false
    /// The AppKit window, for focusing and for matching key events to this browser.
    @ObservationIgnored weak var nsWindow: NSWindow?
    #if DEBUG
    @ObservationIgnored weak var sidebarDragging: SidebarDragging?
    #endif
    /// The window's own traffic lights, hidden while the sidebar shows its copies, and shown in the
    /// title bar that drops down in full screen.
    @ObservationIgnored var titleBarButtons: [NSButton] = []
    /// Listens for the window closing (see `BrowserWindow.configure`); removed when it closes.
    @ObservationIgnored var closeObserver: NSObjectProtocol?

    // MARK: Transient UI state

    /// The floating command bar, when it's open.
    var commandBar: CommandBarMode?
    /// Sidebar docked beside the page. Off, it slides over the page when the pointer reaches the edge.
    var isSidebarDocked: Bool { didSet { Preferences.sidebarDocked = isSidebarDocked } }
    /// The undocked sidebar is showing over the page.
    var isSidebarPeeking = false
    /// The window is in macOS full screen, where the traffic lights also drop down with the menu bar
    /// and minimise is greyed out.
    var isFullScreen = false
    /// True while the sidebar docks or hides. The page keeps one size meanwhile and resizes once.
    private(set) var isSidebarMoving = false
    var sidebarWidth: CGFloat { didSet { Preferences.sidebarWidth = sidebarWidth } }
    /// Find on page, when the find bar is open.
    var find: FindState?
    /// The page find last searched, so its marks can be cleared after a tab switch.
    @ObservationIgnored weak var findPage: (any EnginePage)?
    /// Bumped to put the cursor in the find field.
    var findFocusRequest: UUID?
    var toast: String?
    /// Buttons on the toast, e.g. "Keep in Personal" after Space Routing moved a tab.
    var toastActions: [ToastAction] = []
    @ObservationIgnored var isCapturingPage = false
    /// A link opened for a quick look over the page using the configured click modifier, not yet a tab.
    var glance: GlanceSession?
    var activePrompt: Prompt?
    var siteStyleHost: String?
    /// Reader, when it's showing over the current tab.
    var reader: ReaderSession?
    var isArchivePresented = false
    /// A page to show in the Library (a plugin, pack or extension id), from a ark://library/… link.
    var libraryTarget: String?
    /// Bumped with each request, so asking for the same page twice still opens it.
    var libraryRequest = 0
    /// When and which way the space last changed, so tab lists cascade in from that side.
    private(set) var lastSpaceSwitch: SpaceSwitch?
    /// The right-hand panel each space last showed. It pushes the page over, never covers it.
    private var panels: [UUID: String] = [:]
    var panelWidth: CGFloat { didSet { Preferences.panelWidth = panelWidth } }
    /// The first-launch intro's current phase, while it plays.
    var intro: IntroPhase?
    @ObservationIgnored var introTask: Task<Void, Never>?
    /// The page card's view, so the intro can settle exactly onto it.
    @ObservationIgnored weak var pageCardView: NSView?

    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var sidebarMoveTask: Task<Void, Never>?
    @ObservationIgnored var promptQueue: [(Prompt, CheckedContinuation<EngineDialogResponse, Never>)] = []
    @ObservationIgnored private var spaceBeforePrivate: UUID?
    @ObservationIgnored var lastCookieToastURL: URL?

    init(library: Library, windowKey: UUID = UUID(), isNewWindow: Bool = true, splits: [UUID: TabSplit] = [:],
         splitSpace: UUID? = nil) {
        self.library = library
        self.windowKey = windowKey
        self.isNewWindow = isNewWindow
        splitBySpace = splits
        isSidebarDocked = Preferences.sidebarDocked
        sidebarWidth = max(Preferences.sidebarWidth, Sidebar.minimumWidth)
        panelWidth = Preferences.panelWidth
        let request = library.takeWindowRequest()
        let isFirst = library.windows.isEmpty
        let launch = library.regularSpaces.first { $0.id == library.launchSpaceID } ?? library.regularSpaces[0]
        let nearby = library.activeWindow.map { $0.currentSpace }.flatMap { $0.isPrivate ? nil : $0 }
        let restored = splitSpace.flatMap { id in splits[id] == nil ? nil : library.regularSpaces.first { $0.id == id } }
        selectedSpaceID = (restored ?? (isFirst ? launch : nearby ?? launch)).id
        library.register(self)

        switch request {
        case .tab(let tab):
            if let space = library.space(containing: tab) {
                library.window(showing: tab)?.moveOff(tab, in: space)
                if !tab.isPinned, tab.favoriteID == nil { tab.windowKey = windowKey }
                select(tab)
            }
        case .externalLink(let url, let spaceID):
            newTab(url: url, in: regularSpaces.first { $0.id == spaceID }, source: .link)
        case .privateTab:
            newTab(url: nil, isPrivate: true)
            commandBar = .editCurrent
        case nil:
            if isFirst {
                // The first window picks up where Ark left off. The very first launch says hello.
                resolveSelection(in: currentSpace)
                let env = ProcessInfo.processInfo.environment
                if env["ARK_WELCOME"] == "1" || (!Preferences.hasSeenWelcome && env["ARK_SNAPSHOT"] == nil) {
                    openWelcome(playingIntro: true)
                }
            } else {
                if !splits.isEmpty { resolveSelection(in: currentSpace) }
                if currentTab == nil { commandBar = .newTab }
            }
        }
    }

    // MARK: Shared state, as this window sees it

    var spaces: [Space] { library.spaces }
    var regularSpaces: [Space] { library.regularSpaces }
    var privateSpace: Space? { library.privateSpace }
    var favorites: [Favorite] { library.favorites(for: currentSpace.websiteProfileID) }
    var sortedFavorites: [Favorite] { library.sortedFavorites(for: currentSpace.websiteProfileID) }
    var archive: [BrowserTab] { library.archive }
    var settings: BrowserSettings {
        get { library.settings }
        set { library.settings = newValue }
    }
    var downloads: [EngineDownload] { library.downloads }
    var filterStatus: FilterStatus { library.filterStatus }
    var recentlyClosed: [BrowserTab] { library.recentlyClosed }
    var engine: any BrowserEngine { library.engine }
    var history: HistoryStore { library.history }
    var suggest: SuggestEngine { library.makeSuggestEngine(for: self) }

    func space(containing tab: BrowserTab) -> Space? { library.space(containing: tab) }
    func controller(for tab: BrowserTab) -> TabController { library.controller(for: tab) }
    func isFavorite(_ url: URL) -> Bool { library.isFavorite(url, profileID: currentSpace.websiteProfileID) }
    func addFavorite(url: URL, title: String) { library.addFavorite(url: url, title: title, profileID: currentSpace.websiteProfileID) }
    func removeFavorite(_ fav: Favorite) { library.removeFavorite(fav, profileID: currentSpace.websiteProfileID) }
    func moveFavorite(_ fav: Favorite, before target: Favorite?) { library.moveFavorite(fav, before: target, profileID: currentSpace.websiteProfileID) }
    func togglePinned(_ tab: BrowserTab) { library.togglePinned(tab) }
    func move(_ tab: BrowserTab, to space: Space) { library.move(tab, to: space) }
    func move(_ tab: BrowserTab, before target: BrowserTab?, pinned: Bool) {
        library.move(tab, before: target, pinned: pinned, fallback: currentSpace)
    }
    func deleteSpace(_ space: Space) { library.deleteSpace(space) }
    func closePrivateSpace() { library.closePrivateSpace() }
    func forgetPermissions(for host: String) { library.forgetPermissions(for: host) }
    func updateFilters(force: Bool) async { await library.updateFilters(force: force) }
    func scheduleSave() { library.scheduleSave() }
    func saveNow() { library.saveNow() }

    // MARK: Selection

    private struct PinAssignment: Equatable {
        let tabID: UUID
        let folderID: UUID?
    }

    private struct PinMoveUndo {
        let space: Space
        let tabs: [BrowserTab]
        let folders: [PinFolder]
        let assignments: [PinAssignment]
        let afterTabIDs: [UUID]
        let afterFolders: [PinFolder]
        let afterAssignments: [PinAssignment]
    }

    /// Plain click keeps Ark's normal single-tab behavior. Command-click toggles a pin in the
    /// selection; Shift-click selects the range between the last anchor and this pin.
    func clickSidebarTab(_ tab: BrowserTab, modifiers: NSEvent.ModifierFlags) {
        let flags = modifiers.intersection(.deviceIndependentFlagsMask)
        guard tab.isPinned, !currentSpace.isPrivate, flags.contains(.command) || flags.contains(.shift) else {
            selectedSidebarPinIDs.removeAll()
            sidebarPinSelectionAnchor = nil
            select(tab)
            return
        }
        guard space(containing: tab)?.id == currentSpace.id else { return }
        let ordered = visibleSidebarPinnedTabs(in: currentSpace)
        if flags.contains(.shift) {
            let anchor = sidebarPinSelectionAnchor.flatMap { id in ordered.firstIndex { $0.id == id } }
                ?? ordered.firstIndex { $0.id == tab.id }
            guard let anchor, let target = ordered.firstIndex(where: { $0.id == tab.id }) else { return }
            selectedSidebarPinIDs = Set(ordered[min(anchor, target)...max(anchor, target)].map(\.id))
        } else {
            if selectedSidebarPinIDs.isEmpty { sidebarPinSelectionAnchor = tab.id }
            if !selectedSidebarPinIDs.insert(tab.id).inserted {
                selectedSidebarPinIDs.remove(tab.id)
                if selectedSidebarPinIDs.isEmpty { sidebarPinSelectionAnchor = nil }
            }
        }
    }

    func selectedSidebarPins(for tab: BrowserTab) -> [BrowserTab] {
        guard tab.isPinned, selectedSidebarPinIDs.contains(tab.id),
              space(containing: tab)?.id == currentSpace.id else { return [tab] }
        return visibleSidebarPinnedTabs(in: currentSpace).filter { selectedSidebarPinIDs.contains($0.id) }
    }

    private func visibleSidebarPinnedTabs(in space: Space) -> [BrowserTab] {
        let folders = Dictionary(grouping: space.pinFolders, by: \.parentID)
        var visible: [BrowserTab] = []
        func appendFolders(inside parentID: UUID?) {
            for folder in folders[parentID] ?? [] where !folder.isCollapsed {
                appendFolders(inside: folder.id)
                visible.append(contentsOf: space.pinned.filter { $0.pinFolderID == folder.id })
            }
        }
        appendFolders(inside: nil)
        visible.append(contentsOf: space.rootPins)
        return visible
    }

    func moveSelectedPins(into folderID: UUID?) {
        let space = currentSpace
        let tabs = visibleSidebarPinnedTabs(in: space).filter { selectedSidebarPinIDs.contains($0.id) }
        guard tabs.count > 1, !space.isPrivate else { return }
        let beforeTabs = space.pinned
        let beforeFolders = space.pinFolders
        let beforeAssignments = Self.pinAssignments(in: space)
        guard space.movePinnedTabs(tabs.map(\.id), into: folderID) != nil else { return }
        finishPinMoveUndo(space: space, beforeTabs: beforeTabs, beforeFolders: beforeFolders,
                          beforeAssignments: beforeAssignments)
        selectedSidebarPinIDs.removeAll()
        sidebarPinSelectionAnchor = nil
        library.scheduleSave()
        showToast("Moved \(tabs.count) pinned tabs · ⌘Z to undo")
    }

    func beginPinFolderForSelectedPins(from tab: BrowserTab) {
        let tabs = selectedSidebarPins(for: tab)
        guard tabs.count > 1, tabs.allSatisfy(\.isPinned), !currentSpace.isPrivate else { return }
        pendingPinFolderIDs = Set(tabs.map(\.id))
        pendingPinFolderSpaceID = currentSpace.id
        newPinFolderName = ""
        isCreatingPinFolderForSelection = true
    }

    func createPinFolderForSelectedPins() {
        guard let spaceID = pendingPinFolderSpaceID,
              let space = spaces.first(where: { $0.id == spaceID }), !space.isPrivate else { return }
        let tabs = visibleSidebarPinnedTabs(in: space).filter { pendingPinFolderIDs.contains($0.id) }
        guard tabs.count > 1 else { return }
        let beforeTabs = space.pinned
        let beforeFolders = space.pinFolders
        let beforeAssignments = Self.pinAssignments(in: space)
        guard let folder = space.addPinFolder(named: newPinFolderName),
              space.movePinnedTabs(tabs.map(\.id), into: folder.id) != nil else { return }
        finishPinMoveUndo(space: space, beforeTabs: beforeTabs, beforeFolders: beforeFolders,
                          beforeAssignments: beforeAssignments)
        pendingPinFolderIDs.removeAll()
        pendingPinFolderSpaceID = nil
        selectedSidebarPinIDs.removeAll()
        sidebarPinSelectionAnchor = nil
        library.scheduleSave()
        showToast("Created \(folder.name) with \(tabs.count) pins · ⌘Z to undo")
    }

    var canUndoSidebarPinMove: Bool {
        guard let undo = pinMoveUndo, undo.space.pinned.map(\.id) == undo.afterTabIDs,
              undo.space.pinFolders == undo.afterFolders,
              Self.pinAssignments(in: undo.space) == undo.afterAssignments else { return false }
        return true
    }

    func undoSidebarPinMove() {
        guard canUndoSidebarPinMove, let undo = pinMoveUndo else { pinMoveUndo = nil; return }
        guard undo.space.restorePinnedOrganization(undo.tabs, folders: undo.folders,
                                                   folderIDs: Self.folderMap(undo.assignments)) else {
            pinMoveUndo = nil
            return
        }
        pinMoveUndo = nil
        selectedSidebarPinIDs.removeAll()
        sidebarPinSelectionAnchor = nil
        library.scheduleSave()
        showToast("Pin move undone")
    }

    func clearSidebarPinMoveUndo() { pinMoveUndo = nil }

    func clearSidebarPinSelection() {
        selectedSidebarPinIDs.removeAll()
        sidebarPinSelectionAnchor = nil
    }

    private func finishPinMoveUndo(space: Space, beforeTabs: [BrowserTab], beforeFolders: [PinFolder],
                                   beforeAssignments: [PinAssignment]) {
        pinMoveUndo = PinMoveUndo(space: space, tabs: beforeTabs, folders: beforeFolders,
                                  assignments: beforeAssignments, afterTabIDs: space.pinned.map(\.id),
                                  afterFolders: space.pinFolders, afterAssignments: Self.pinAssignments(in: space))
    }

    private static func pinAssignments(in space: Space) -> [PinAssignment] {
        space.pinned.map { PinAssignment(tabID: $0.id, folderID: $0.pinFolderID) }
    }

    private static func folderMap(_ assignments: [PinAssignment]) -> [UUID: UUID?] {
        var result: [UUID: UUID?] = [:]
        for assignment in assignments { result.updateValue(assignment.folderID, forKey: assignment.tabID) }
        return result
    }

    var currentSpace: Space { spaces.first { $0.id == selectedSpaceID } ?? regularSpaces[0] }

    var currentTab: BrowserTab? {
        let space = currentSpace
        guard let id = tabSelection[space.id] else { return nil }
        return space.allTabs.first { $0.id == id && lists($0) }
    }

    /// Whether this window's sidebar lists a tab: pinned and favourite tabs in every window,
    /// Today tabs only in the window they belong to (see `Library.owner(of:)`).
    func lists(_ tab: BrowserTab) -> Bool {
        tab.isPinned || tab.favoriteID != nil || library.owner(of: tab) === self
    }

    /// This window's Today tabs in a space, without the ones favourite tiles hold.
    func listedToday(in space: Space) -> [BrowserTab] { space.listedToday.filter(lists) }

    /// This window's Today tabs in a space, favourite tabs included.
    func today(in space: Space) -> [BrowserTab] { space.today.filter(lists) }

    var currentController: TabController? { currentTab.map(controller(for:)) }

    /// The tab this window shows (or last showed) in a space.
    func selectedTabID(in space: Space) -> UUID? { tabSelection[space.id] }

    /// Shows a tab. If another window already shows it, that window comes forward instead, like Arc.
    func select(_ tab: BrowserTab) {
        selectedSidebarPinIDs.removeAll()
        sidebarPinSelectionAnchor = nil
        if let other = library.window(showing: tab), other !== self {
            other.nsWindow?.makeKeyAndOrderFront(nil)
            return
        }
        // Another window's Today tab opens over there.
        if library.isOwnedElsewhere(tab, than: self), let owner = library.owner(of: tab), owner !== self {
            owner.select(tab)
            owner.nsWindow?.makeKeyAndOrderFront(nil)
            return
        }
        guard let space = space(containing: tab) else { return }
        // A Today tab no open window owns becomes this window's.
        if !tab.isPinned, tab.favoriteID == nil, tab.windowKey != windowKey { tab.windowKey = windowKey }
        if space.id != selectedSpaceID { selectSpace(space, resolving: false) }
        setSelection(tab, in: space)
        tab.lastActive = .now
        dismissFind()
        reader = nil
        library.existingController(for: tab)?.recoverIfNeeded()
        scheduleSave()
    }

    func selectSpace(_ space: Space) { selectSpace(space, resolving: true) }

    private func selectSpace(_ space: Space, resolving: Bool) {
        guard space.id != selectedSpaceID else { return }
        selectedSidebarPinIDs.removeAll()
        sidebarPinSelectionAnchor = nil
        if library.browsingProfile(in: currentSpace) != library.browsingProfile(in: space) {
            closeGlance()
            commandBar = nil
        }
        if space.isPrivate, !currentSpace.isPrivate { spaceBeforePrivate = selectedSpaceID }
        if let from = spaces.firstIndex(where: { $0.id == selectedSpaceID }),
           let to = spaces.firstIndex(where: { $0.id == space.id }) {
            lastSpaceSwitch = SpaceSwitch(at: .now, forward: to > from)
        }
        selectedSpaceID = space.id
        if resolving { resolveSelection(in: space) }
        dismissFind()
        reader = nil
        toast = nil
        scheduleSave()
    }

    /// First visit to a space in this window: show the tab the space last had, unless another window has it.
    private func resolveSelection(in space: Space) {
        if let remembered = tabSelection[space.id] {
            let busy = library.windows.contains { $0 !== self && $0.isShowing(remembered) }
            if var pair = splitBySpace[space.id], pair.isOpen, !canShowSplit(pair, in: space) {
                pair.isOpen = false
                splitBySpace[space.id] = pair
            }
            if !busy { return }
            tabSelection[space.id] = nil
        }
        if let pair = splitBySpace[space.id], splitMembers(of: pair, in: space) != nil {
            // Scene storage keeps this window's presentation even if another window changed the Space's selection.
            if pair.isOpen, canShowSplit(pair, in: space) {
                tabSelection[space.id] = pair.contains(pair.focused) ? pair.focused : pair.first
                return
            }
        } else {
            splitBySpace[space.id] = nil
        }
        // The space's last tab if it's this window's, else this window's most recent one there.
        let mine = { (t: BrowserTab) in t.isPinned || t.favoriteID != nil || t.windowKey == self.windowKey }
        let candidates = [space.selectedTab].compactMap { $0 }.filter(mine)
            + today(in: space).filter { $0.windowKey == windowKey }.sorted { $0.lastActive > $1.lastActive }
            + [space.selectedTab].compactMap { $0 }.filter(lists)
        guard let tab = candidates.first(where: { library.window(showing: $0) == nil }) else { return }
        tabSelection[space.id] = tab.id
    }

    private func setSelection(_ tab: BrowserTab?, in space: Space) {
        if let previous = tabSelection[space.id], previous != tab?.id {
            lastUsedTabIDs[space.id] = previous
        }
        tabSelection[space.id] = tab?.id
        library.videoMiniPlayer.selected(tab, in: self)
        if var split = splitBySpace[space.id] {
            split.isOpen = tab.map { split.contains($0.id) && canShowSplit(split, in: space) } ?? false
            if let tab, split.isOpen { split.focused = tab.id }
            if splitBySpace[space.id] != split { splitBySpace[space.id] = split }
        }
        // Remembered with the space, for the next launch.
        space.selectedTabID = tab?.id
        if let tab, let c = library.existingController(for: tab) { engine.pageDidBecomeActive(c.page) }
    }

    /// `tab` is going away from this window (closed, moved, or opened in another window).
    /// Arc moves to the tab below, then above.
    func moveOff(_ tab: BrowserTab, in space: Space, closing: Bool = false) {
        let partner = detachSplit(containing: tab, in: space)
        guard tabSelection[space.id] == tab.id else { return }
        if selectedSpaceID == space.id { dismissFind(); reader = nil }
        if let partner {
            setSelection(partner, in: space)
            return
        }
        if closing, Preferences.closeTabGoesBack, let previous = lastUsedTab {
            select(previous)
            return
        }
        let list = today(in: space)
        guard !tab.isPinned, let i = list.firstIndex(where: { $0.id == tab.id }) else {
            // Leaving a pinned tab only unloads it, like Arc.
            setSelection(nil, in: space)
            return
        }
        let elsewhere = Set(library.windows.filter { $0 !== self }.flatMap(\.visibleTabIDs))
        let free = { (t: BrowserTab) in !elsewhere.contains(t.id) && t.id != tab.id }
        let next = list[(i + 1)...].first(where: free)
            ?? list[..<i].reversed().first(where: free)
            ?? space.pinned.last(where: free)
        setSelection(next, in: space)
    }

    /// A tab this window showed was dragged into another space.
    func tabLeft(_ tab: BrowserTab, space: Space) {
        let partner = detachSplit(containing: tab, in: space)
        guard tabSelection[space.id] == tab.id else { return }
        let elsewhere = Set(library.windows.filter { $0 !== self }.flatMap(\.visibleTabIDs))
        setSelection(partner ?? space.allTabs.first { !elsewhere.contains($0.id) && lists($0) }, in: space)
    }

    /// The space this window shows was deleted or closed.
    func leaveSpace() {
        tabSelection[selectedSpaceID] = nil
        lastUsedTabIDs[selectedSpaceID] = nil
        splitBySpace[selectedSpaceID] = nil
        let back = regularSpaces.first { $0.id == spaceBeforePrivate && $0.id != selectedSpaceID }
            ?? regularSpaces.first { $0.id != selectedSpaceID } ?? regularSpaces[0]
        lastSpaceSwitch = SpaceSwitch(at: .now, forward: false)
        selectedSpaceID = back.id
        spaceBeforePrivate = nil
        resolveSelection(in: back)
        dismissFind()
        reader = nil
    }

    /// Pinned then today: the order the sidebar shows and Cmd-1…9 count.
    var orderedTabs: [BrowserTab] { currentSpace.pinned + today(in: currentSpace) }

    func selectTab(number n: Int) {
        let tabs = orderedTabs
        guard !tabs.isEmpty else { return }
        let i = n >= 9 ? tabs.count - 1 : n - 1
        if tabs.indices.contains(i) { select(tabs[i]) }
    }

    func selectAdjacentTab(_ delta: Int) {
        let tabs = orderedTabs
        guard tabs.count > 1 else { return }
        guard let cur = currentTab, let i = tabs.firstIndex(where: { $0.id == cur.id }) else { select(tabs[0]); return }
        select(tabs[(i + delta + tabs.count) % tabs.count])
    }

    var lastUsedTab: BrowserTab? {
        let space = currentSpace
        guard let id = lastUsedTabIDs[space.id], tabSelection[space.id] != id else { return nil }
        guard let previous = space.allTabs.first(where: { $0.id == id && lists($0) }) else { return nil }
        if let owner = library.window(showing: previous), owner !== self { return nil }
        return previous
    }

    func selectLastUsedTab() {
        if let lastUsedTab { select(lastUsedTab) }
    }

    var recentTabs: [BrowserTab] {
        let active = currentTab?.id
        let previous = lastUsedTab?.id
        let shownElsewhere = Set(library.windows.filter { $0 !== self }.flatMap(\.visibleTabIDs))
        return Array(orderedTabs.filter { !shownElsewhere.contains($0.id) }.sorted { left, right in
            if (left.id == active) != (right.id == active) { return left.id == active }
            if (left.id == previous) != (right.id == previous) { return left.id == previous }
            return left.lastActive > right.lastActive
        }.prefix(8))
    }

    func showRecentTabs() {
        guard recentTabs.count > 1 else { return }
        commandBar = nil
        isRecentTabsPresented = true
    }

    func chooseRecentTab(_ id: UUID) {
        guard let tab = recentTabs.first(where: { $0.id == id }) else { return }
        isRecentTabsPresented = false
        select(tab)
    }

    func selectAdjacentSpace(_ delta: Int) {
        let spaces = shownSpaces
        guard spaces.count > 1, let i = spaces.firstIndex(where: { $0.id == selectedSpaceID }) else { return }
        let j = i + delta
        guard spaces.indices.contains(j) else { return }
        selectSpace(spaces[j])
    }

    func selectSpace(number n: Int) {
        let spaces = shownSpaces
        if spaces.indices.contains(n - 1) { selectSpace(spaces[n - 1]) }
    }

    /// Cycles through website profiles that are assigned to regular Spaces.
    func selectAdjacentWebsiteProfile(_ delta: Int) {
        var profileIDs: [UUID?] = []
        if regularSpaces.contains(where: { $0.websiteProfileID == nil }) { profileIDs.append(nil) }
        profileIDs.append(contentsOf: library.settings.websiteProfiles
            .map(\.id)
            .filter { id in regularSpaces.contains(where: { $0.websiteProfileID == id }) })
        guard profileIDs.count > 1,
              let index = profileIDs.firstIndex(where: { $0 == currentSpace.websiteProfileID }) else { return }
        let next = profileIDs[(index + delta + profileIDs.count) % profileIDs.count]
        guard let space = regularSpaces.first(where: { $0.websiteProfileID == next }) else { return }
        selectSpace(space)
    }

    /// The spaces the switcher shows: the Agent space only while it's in use (or you're in it).
    var shownSpaces: [Space] {
        spaces.filter { $0.id == selectedSpaceID || library.agents.showsInSidebar($0) }
    }

    // MARK: Opening tabs

    @discardableResult
    func newTab(url: URL?, in space: Space? = nil, isPrivate: Bool = false,
                source: Frecency.VisitSource = .typed, select shouldSelect: Bool = true,
                promoting glance: GlanceSession? = nil) -> BrowserTab {
        // Space Routing: a site with a rule opens in its Space, unless a Space was asked for or the tab is private.
        var target = space ?? currentSpace
        var routed: SpaceRouter.Match?
        if space == nil, !isPrivate, !currentSpace.isPrivate, let match = SpaceRouter.shared.match(for: url, in: regularSpaces),
           match.space.id != currentSpace.id {
            target = match.space
            routed = match
        }
        let from = currentSpace
        let tab = library.insertTab(url: url, in: target, isPrivate: isPrivate, source: source, for: self, promoting: glance)
        if shouldSelect { select(tab) }
        if let routed { announceRoute(routed, tab: tab, from: from, quiet: shouldSelect) }
        return tab
    }

    /// Opens the pinned pages in a folder and its nested folders behind the current tab, in sidebar order.
    func openAllPinnedTabs(in folder: PinFolder, space: Space) {
        guard space.pinFolders.contains(where: { $0.id == folder.id && $0.feed == nil }) else { return }
        let children = Dictionary(grouping: space.pinFolders, by: \.parentID)
        var urls: [URL] = []
        var visited: Set<UUID> = []
        func collect(_ folderID: UUID) {
            guard visited.insert(folderID).inserted else { return }
            for child in children[folderID] ?? [] { collect(child.id) }
            urls.append(contentsOf: space.pinned.filter { $0.pinFolderID == folderID }.compactMap(\.url))
        }
        collect(folder.id)
        for url in urls.reversed() {
            newTab(url: url, in: space, source: .bookmark, select: false)
        }
    }

    /// Says where a routed tab went. The first time a site moves, with a way to keep it where you were.
    private func announceRoute(_ match: SpaceRouter.Match, tab: BrowserTab, from: Space, quiet: Bool) {
        let first = SpaceRouter.shared.shouldAnnounce(match.pattern)
        guard first || !quiet else { return }
        guard first else { showToast("Opened in \(match.space.name)"); return }
        showToast("Opened \(match.pattern) in \(match.space.name)", actions: [
            ToastAction(title: "Keep in \(from.name)") { [weak self] in
                guard let self else { return }
                SpaceRouter.shared.stop(match)
                self.move(tab, to: from)
                self.select(tab)
            },
        ])
    }

    /// Favourites behave like Arc's: the tile holds its own tab, kept out of the Today list. One
    /// click goes back to that tab, or to a tab already showing the site, or opens one.
    func open(_ favorite: Favorite) {
        if let owned = currentSpace.today.first(where: { $0.favoriteID == favorite.id }) {
            select(owned)
            return
        }
        let key = URLNormalizer.key(for: favorite.url)
        if let existing = currentSpace.allTabs.first(where: { lists($0) && $0.url.map(URLNormalizer.key(for:)) == key }) {
            select(existing)
        } else {
            let tab = newTab(url: favorite.url, source: .bookmark)
            tab.favoriteID = favorite.id
            scheduleSave()
        }
    }

    /// Moves a tab out into a window of its own.
    func openInNewWindow(_ tab: BrowserTab) {
        library.openWindow(.tab(tab))
    }

    // MARK: Closing

    func close(_ tab: BrowserTab) { library.close(tab) }

    func closeOtherTabs(than keep: BrowserTab) {
        for t in listedToday(in: currentSpace) where t.id != keep.id { close(t) }
    }

    func clearableTodayTabs(in space: Space) -> [BrowserTab] {
        let shown = Set(visibleTabIDs)
        return listedToday(in: space).filter { !shown.contains($0.id) }
    }

    /// Clears Today in the current Space while keeping its visible tabs.
    func clearToday() {
        for tab in clearableTodayTabs(in: currentSpace) { close(tab) }
    }

    func reopenClosedTab() {
        guard let tab = library.popRecentlyClosed() else { return }
        tab.lastActive = .now
        let target = currentSpace.isPrivate ? regularSpaces[0] : currentSpace
        tab.windowKey = windowKey
        target.today.insert(tab, at: 0)
        select(tab)
    }

    // MARK: Spaces

    func addSpace() {
        selectSpace(library.addSpace())
    }

    // MARK: Archive

    func restoreFromArchive(_ tab: BrowserTab) {
        library.takeFromArchive(tab, into: currentSpace.isPrivate ? regularSpaces[0] : currentSpace, for: self)
        select(tab)
    }

    // MARK: Sidebar

    /// Call it without `withAnimation`: the split view animates the column itself, and the window's
    /// `.animation(value:)` covers the rest. `withAnimation` first flushes any pending SwiftUI update,
    /// and a change made during that flush was sometimes dropped, so ⌘S (or the button) did nothing.
    func toggleSidebar() {
        // The page holds its width while the sidebar moves, then resizes once (see PageHost).
        sidebarMoveTask?.cancel()
        isSidebarMoving = true
        sidebarMoveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(Motion.dockDuration * 1000) + 40))
            guard !Task.isCancelled else { return }
            self?.isSidebarMoving = false
        }
        isSidebarDocked.toggle()
        isSidebarPeeking = false
    }

    // MARK: Toast

    func showToast(_ text: String, actions: [ToastAction] = []) {
        toastTask?.cancel()
        toast = text
        toastActions = actions
        toastTask = Task { [weak self] in
            // Long enough to reach a button when there is one.
            try? await Task.sleep(for: .seconds(actions.isEmpty ? 1.8 : 6))
            guard !Task.isCancelled else { return }
            self?.toast = nil
            self?.toastActions = []
        }
    }

    func runToastAction(_ action: ToastAction) {
        toastTask?.cancel()
        toast = nil
        toastActions = []
        action.run()
    }

    // MARK: Blocking

    var blockingDisabledForCurrentSite: Bool { settings.blockingDisabled(for: currentTab?.url?.host()) }

    func toggleBlockingForCurrentSite() {
        guard let tab = currentTab, let host = tab.url?.host()?.lowercased() else { return }
        let site = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        if settings.blockingDisabled(for: host) {
            settings.blockingDisabledHosts = settings.blockingDisabledHosts.filter { host != $0 && !host.hasSuffix("." + $0) }
            showToast("Blockers on for \(site)")
        } else {
            settings.blockingDisabledHosts.insert(site)
            showToast("Blockers off for \(site)")
        }
        Task { @MainActor in
            await library.blockingApplied()
            controller(for: tab).page.reload()
        }
    }

    func clearWebsiteData() async {
        await library.clearWebsiteData()
        showToast("Website data cleared")
    }
}

// MARK: - Small types

enum CommandBarMode: Equatable {
    /// Cmd-T: opens what you pick in a new tab.
    case newTab
    /// Cmd-L or a click on the address: replaces the current page.
    case editCurrent
    /// Cmd-K: tools and commands first, the web only as a fallback.
    case commands
}

struct SpaceSwitch: Equatable {
    let at: Date
    let forward: Bool
}

struct FindState: Equatable {
    var text = ""
    var found: Bool?
    /// "3 of 12", when the engine can count.
    var matches: FindMatches?
}

/// What a new window should show first.
enum WindowRequest {
    case tab(BrowserTab)
    case externalLink(URL, spaceID: UUID)
    case privateTab
}

/// Preferences that aren't part of the synced browser state.
enum Preferences {
    private static var d: UserDefaults { .standard }
    static let externalLinksInPreviewKey = "externalLinksInPreview"
    static var externalLinksInPreview: Bool { d.bool(forKey: externalLinksInPreviewKey) }
    static let automaticVideoPiPKey = "automaticVideoPiP"
    static var automaticVideoPiP: Bool { d.bool(forKey: automaticVideoPiPKey) }
    static let videoKeyControlsKey = "videoKeyControls"
    static var videoKeyControls: Bool { d.bool(forKey: videoKeyControlsKey) }
    static let pinnedLinksOpenInNewTabKey = "pinnedLinksOpenInNewTab"
    static var pinnedLinksOpenInNewTab: Bool {
        get { d.bool(forKey: pinnedLinksOpenInNewTabKey) }
        set { d.set(newValue, forKey: pinnedLinksOpenInNewTabKey) }
    }
    static let closeTabGoesBackKey = "closeTabGoesBack"
    static var closeTabGoesBack: Bool {
        get { d.bool(forKey: closeTabGoesBackKey) }
        set { d.set(newValue, forKey: closeTabGoesBackKey) }
    }
    static var linkPreviewModifier: LinkPreviewModifier {
        get { d.string(forKey: "linkPreviewModifier").flatMap(LinkPreviewModifier.init(rawValue:)) ?? .option }
        set { d.set(newValue.rawValue, forKey: "linkPreviewModifier") }
    }

    /// Set once the welcome tab has opened, so the intro plays on first launch only.
    static var hasSeenWelcome: Bool {
        get { d.bool(forKey: "hasSeenWelcome") }
        set { d.set(newValue, forKey: "hasSeenWelcome") }
    }

    /// Extension ids pinned to the address pill; nil until the user first pins or unpins one.
    static var pinnedExtensions: Set<String>? {
        get { (d.array(forKey: "pinnedExtensions") as? [String]).map(Set.init) }
        set { d.set(newValue.map { Array($0).sorted() }, forKey: "pinnedExtensions") }
    }

    /// The Settings tab to show next, so other places can open Settings on a given tab.
    static var settingsTab: String {
        get { d.string(forKey: "settingsTab") ?? "general" }
        set { d.set(newValue, forKey: "settingsTab") }
    }

    static var panelWidth: CGFloat {
        get { (d.object(forKey: "panelWidth") as? Double).map { CGFloat($0) } ?? 320 }
        set { d.set(Double(newValue), forKey: "panelWidth") }
    }

    static var sidebarDocked: Bool {
        get { d.object(forKey: "sidebarDocked") as? Bool ?? true }
        set { d.set(newValue, forKey: "sidebarDocked") }
    }

    static var sidebarWidth: CGFloat {
        get { (d.object(forKey: "sidebarWidth") as? Double).map { CGFloat($0) } ?? 260 }
        set { d.set(Double(newValue), forKey: "sidebarWidth") }
    }

    /// On by default: asking sites not to sell or share your data costs nothing.
    static var globalPrivacyControl: Bool {
        get { d.object(forKey: "globalPrivacyControl") as? Bool ?? true }
        set { d.set(newValue, forKey: "globalPrivacyControl") }
    }

    static var clearDataOnQuit: Bool {
        get { d.bool(forKey: "clearDataOnQuit") }
        set { d.set(newValue, forKey: "clearDataOnQuit") }
    }

    /// Safari web extensions installed on this Mac (1Password for Safari and the like). On in Debug builds.
    /// Experimental and off: most Safari extensions are companions to a Mac app, and that link
    /// doesn't work in Ark. Settings › Engine has the switch.
    static var useSafariExtensions: Bool {
        get {
            // Everyone starts again with it off, once, including people who had it on.
            if !d.bool(forKey: "safariExtensionsReset1") {
                d.set(true, forKey: "safariExtensionsReset1")
                d.set(false, forKey: "useSafariExtensions")
            }
            return d.bool(forKey: "useSafariExtensions")
        }
        set { d.set(newValue, forKey: "useSafariExtensions") }
    }

    /// Settings › Audio: how Ark processes the mic on calls.
    static var callAudio: CallAudioTuning {
        get {
            var t = (d.data(forKey: "callAudio")).flatMap { try? JSONDecoder().decode(CallAudioTuning.self, from: $0) } ?? CallAudioTuning()
            // The spike's old switch: `defaults write <bundle id> callAudioProcessing -bool NO`.
            if d.data(forKey: "callAudio") == nil, d.object(forKey: "callAudioProcessing") as? Bool == false { t.processing = .system }
            // tools/audio-bench picks the in-page processing per run (test builds only).
            if AudioBench.isEnabled, let v = ProcessInfo.processInfo.environment["ARK_AUDIO_BENCH_CALL_AUDIO"], let p = CallAudioTuning.Processing(rawValue: v) { t.processing = p }
            // The in-page script is retired from Settings: calls get the Ark Audio Engine (inside WebKit) or Apple's
            // processing. Only the test bench can still pick it.
            if !(AudioBench.isEnabled && ProcessInfo.processInfo.environment["ARK_AUDIO_BENCH_CALL_AUDIO"] != nil) { t.processing = .system }
            return t
        }
        set { d.set(try? JSONEncoder().encode(newValue), forKey: "callAudio") }
    }

    /// Inspect Element in the page's context menu. On in Debug builds.
    static var developerTools: Bool {
        get {
            #if DEBUG
            d.object(forKey: "developerTools") as? Bool ?? true
            #else
            d.bool(forKey: "developerTools")
            #endif
        }
        set { d.set(newValue, forKey: "developerTools") }
    }

    /// Reader text size, shared by every article.
    static var readerScale: Double {
        get { d.object(forKey: "readerScale") as? Double ?? 1 }
        set { d.set(newValue, forKey: "readerScale") }
    }

    /// Page zoom per site, like Safari remembers it.
    static func zoom(for host: String) -> Double {
        (d.dictionary(forKey: "siteZoom")?[host] as? Double) ?? 1
    }

    static func setZoom(_ zoom: Double, for host: String) {
        var all = d.dictionary(forKey: "siteZoom") ?? [:]
        all[host] = abs(zoom - 1) < 0.01 ? nil : zoom
        d.set(all, forKey: "siteZoom")
    }
}

// MARK: - Right panel

extension Browser {
    /// The tool showing in the right-hand panel, by `Tool.id`, for this space.
    var panel: String? {
        get { panels[selectedSpaceID] }
        set {
            panels[selectedSpaceID] = newValue
            if let newValue { Preferences.lastPanelTool = newValue }
        }
    }

    /// ⌥⌘S: shows the tool this window last had (Notes the first time), or hides the panel.
    func togglePanel() {
        withAnimation(Motion.dock) {
            panel = panel == nil ? (library.workbench.tool(Preferences.lastPanelTool)?.id ?? "notes") : nil
        }
    }

    /// Opens a tool in the panel, or hides the panel if that tool is already showing.
    func showPanel(_ id: String, toggles: Bool = false) {
        withAnimation(Motion.dock) { panel = toggles && panel == id ? nil : id }
    }

    /// Sets the panel a space opens with, without touching the space on screen.
    func setPanel(_ id: String, for space: Space, ifUnset: Bool) {
        if ifUnset, panels[space.id] != nil { return }
        panels[space.id] = id
    }

    /// An agent is waiting on you: bring up the Agents panel here, without taking the keyboard.
    func showAgentsPanel() {
        if panel != "agents" { showPanel("agents") }
    }
}

extension Preferences {
    static var lastPanelTool: String {
        get { UserDefaults.standard.string(forKey: "lastPanelTool") ?? "notes" }
        set { UserDefaults.standard.set(newValue, forKey: "lastPanelTool") }
    }
}

/// A button on a toast.
struct ToastAction: Identifiable {
    let id = UUID()
    let title: String
    let run: @MainActor () -> Void
}
