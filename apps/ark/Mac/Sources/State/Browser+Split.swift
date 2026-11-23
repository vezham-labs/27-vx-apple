import AppKit
import BrowserCore

struct TabSplit: Codable, Equatable {
    enum Axis: String, Codable { case sideBySide, stacked }

    let first: UUID
    let second: UUID
    var axis: Axis = .sideBySide
    var fraction = 0.5
    var focused: UUID
    var isOpen = true

    func contains(_ id: UUID) -> Bool { id == first || id == second }
}

extension Browser {
    var splitCandidates: [BrowserTab] {
        guard let active = currentTab, canSplit(active) else { return [] }
        return currentSpace.today.filter { $0.id != active.id && canSplit($0) }
    }

    var activeSplit: TabSplit? {
        let space = currentSpace
        guard let pair = splitBySpace[space.id], pair.isOpen,
              let focused = selectedTabID(in: space), pair.contains(focused),
              splitMembers(of: pair, in: space) != nil else { return nil }
        return pair
    }

    var visibleTabIDs: [UUID] {
        if let pair = activeSplit { return [pair.first, pair.second] }
        return currentTab.map { [$0.id] } ?? []
    }

    func isShowing(_ tabID: UUID) -> Bool {
        if let pair = activeSplit { return pair.contains(tabID) }
        return currentTab?.id == tabID
    }

    func splitMembers(of pair: TabSplit, in space: Space) -> (BrowserTab, BrowserTab)? {
        guard pair.first != pair.second, !space.isPrivate,
              let first = space.today.first(where: { $0.id == pair.first }), canSplit(first),
              let second = space.today.first(where: { $0.id == pair.second }), canSplit(second) else { return nil }
        return (first, second)
    }

    func splitWith(_ tab: BrowserTab) {
        guard let active = currentTab, active.id != tab.id,
              let space = space(containing: tab), space.id == currentSpace.id,
              canSplit(active), canSplit(tab) else { return }
        splitBySpace[space.id] = TabSplit(first: active.id, second: tab.id, focused: active.id)
        reader = nil
        isSplitPickerPresented = false
    }

    func focusSplitPane(_ tab: BrowserTab) {
        guard let split = activeSplit, split.contains(tab.id), tab.id != currentTab?.id else { return }
        select(tab)
        if commandBar == nil, let page = currentController?.page.view, page.window === nsWindow {
            nsWindow?.makeFirstResponder(page)
        }
    }

    func setSplitAxis(_ axis: TabSplit.Axis) {
        guard var split = activeSplit else { return }
        split.axis = axis
        splitBySpace[currentSpace.id] = split
    }

    func resizeSplit(to fraction: Double) {
        guard var split = activeSplit, fraction.isFinite else { return }
        split.fraction = min(0.8, max(0.2, fraction))
        splitBySpace[currentSpace.id] = split
    }

    func separateSplit() {
        splitBySpace[currentSpace.id] = nil
    }

    func detachSplit(containing tab: BrowserTab, in space: Space) -> BrowserTab? {
        guard let split = splitBySpace[space.id], split.contains(tab.id) else { return nil }
        splitBySpace[space.id] = nil
        let other = split.first == tab.id ? split.second : split.first
        return space.today.first { $0.id == other && canSplit($0) }
    }

    private func canSplit(_ tab: BrowserTab) -> Bool {
        guard !tab.isPrivate, !tab.isPinned, tab.favoriteID == nil, tab.windowKey == windowKey,
              let scheme = tab.url?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
}
