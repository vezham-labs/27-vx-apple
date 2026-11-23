import AppKit
import BrowserCore

struct TabSplit: Codable, Equatable {
    enum Axis: String, Codable { case sideBySide, stacked }

    static let maxPanes = 4
    var first: UUID
    var second: UUID
    var additional: [UUID]?
    var customShares: [Double]?
    var axis: Axis = .sideBySide
    var fraction = 0.5
    var focused: UUID
    var isOpen = true

    var tabs: [UUID] { [first, second] + (additional ?? []) }
    var minimumShare: Double { tabs.count > 2 ? 0.1 : 0.2 }
    var shares: [Double] {
        let count = tabs.count
        if count == 2 {
            let first = min(0.8, max(0.2, fraction.isFinite ? fraction : 0.5))
            return [first, 1 - first]
        }
        guard let customShares, customShares.count == count,
              customShares.allSatisfy({ $0.isFinite && $0 >= minimumShare - 0.0001 }),
              abs(customShares.reduce(0, +) - 1) < 0.0001 else {
            return Array(repeating: 1 / Double(count), count: count)
        }
        return customShares
    }

    func contains(_ id: UUID) -> Bool { tabs.contains(id) }

    func resizedShares(after index: Int, by delta: Double) -> [Double] {
        var shares = self.shares
        guard index >= 0, index + 1 < shares.count, delta.isFinite else { return shares }
        let change = min(shares[index + 1] - minimumShare, max(minimumShare - shares[index], delta))
        shares[index] += change
        shares[index + 1] -= change
        return shares
    }

    mutating func setShares(_ shares: [Double]) {
        if shares.count == 2 { fraction = shares[0]; customShares = nil }
        else { customShares = shares }
    }

    mutating func setTabs(_ tabs: [UUID]) {
        first = tabs[0]
        second = tabs[1]
        additional = tabs.count > 2 ? Array(tabs.dropFirst(2)) : nil
        equalise()
    }

    mutating func equalise() { fraction = 0.5; customShares = nil }
}

extension Browser {
    var splitCandidates: [BrowserTab] {
        guard let active = currentTab, canSplit(active) else { return [] }
        let elsewhere = Set(library.windows.filter { $0 !== self }.flatMap(\.visibleTabIDs))
        return currentSpace.allTabs.filter { $0.id != active.id && canSplit($0) && !elsewhere.contains($0.id) }
    }

    var additionalSplitCandidates: [BrowserTab] {
        guard let split = activeSplit, split.tabs.count < TabSplit.maxPanes else { return [] }
        return splitCandidates.filter { !split.contains($0.id) }
    }

    var activeSplit: TabSplit? {
        let space = currentSpace
        guard let pair = splitBySpace[space.id], pair.isOpen,
              let focused = selectedTabID(in: space), pair.contains(focused),
              splitMembers(of: pair, in: space) != nil else { return nil }
        return pair
    }

    var visibleTabIDs: [UUID] {
        if let pair = activeSplit { return pair.tabs }
        return currentTab.map { [$0.id] } ?? []
    }

    func isShowing(_ tabID: UUID) -> Bool {
        if let pair = activeSplit { return pair.contains(tabID) }
        return currentTab?.id == tabID
    }

    func splitMembers(of pair: TabSplit, in space: Space) -> [BrowserTab]? {
        let ids = pair.tabs
        guard !space.isPrivate, ids.count <= TabSplit.maxPanes, Set(ids).count == ids.count else { return nil }
        let members = ids.compactMap { splitMember($0, in: space) }
        return members.count == ids.count ? members : nil
    }

    func canShowSplit(_ pair: TabSplit, in space: Space) -> Bool {
        guard let members = splitMembers(of: pair, in: space) else { return false }
        let pinned = members.filter(\.isPinned)
        return !library.windows.contains { window in window !== self && pinned.contains { window.isShowing($0.id) } }
    }

    func splitWith(_ tab: BrowserTab) {
        guard let active = currentTab, active.id != tab.id,
              let space = space(containing: tab), space.id == currentSpace.id,
              canSplit(active), canSplit(tab) else { return }
        let pair = TabSplit(first: active.id, second: tab.id, focused: active.id)
        guard canShowSplit(pair, in: space) else { return }
        splitBySpace[space.id] = pair
        reader = nil
        isSplitPickerPresented = false
    }

    func addToSplit(_ tab: BrowserTab) {
        guard var split = activeSplit, additionalSplitCandidates.contains(where: { $0 === tab }) else { return }
        split.setTabs(split.tabs + [tab.id])
        splitBySpace[currentSpace.id] = split
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
        guard var split = activeSplit, split.tabs.count == 2, fraction.isFinite else { return }
        split.fraction = min(0.8, max(0.2, fraction))
        splitBySpace[currentSpace.id] = split
    }

    func resizeSplit(after index: Int, by delta: Double) {
        guard var split = activeSplit else { return }
        split.setShares(split.resizedShares(after: index, by: delta))
        splitBySpace[currentSpace.id] = split
    }

    func equaliseSplit() {
        guard var split = activeSplit else { return }
        split.equalise()
        splitBySpace[currentSpace.id] = split
    }

    func separateSplit() {
        splitBySpace[currentSpace.id] = nil
    }

    func detachSplit(containing tab: BrowserTab, in space: Space) -> BrowserTab? {
        guard var split = splitBySpace[space.id], let index = split.tabs.firstIndex(of: tab.id) else { return nil }
        var remaining = split.tabs
        remaining.remove(at: index)
        let other = remaining[min(index, remaining.count - 1)]
        let partner = splitMember(other, in: space).flatMap { candidate in
            library.windows.contains { $0 !== self && candidate.isPinned && $0.isShowing(other) } ? nil : candidate
        }
        splitBySpace[space.id] = nil
        if remaining.count >= 2 {
            var shares = split.shares
            shares.remove(at: index)
            let total = shares.reduce(0, +)
            split.setTabs(remaining)
            split.setShares(shares.map { $0 / total })
            if split.focused == tab.id { split.focused = partner?.id ?? remaining[0] }
            if canShowSplit(split, in: space) { splitBySpace[space.id] = split }
        }
        return partner
    }

    private func splitMember(_ id: UUID, in space: Space) -> BrowserTab? {
        let tab = space.pinned.first { $0.id == id } ?? space.today.first { $0.id == id }
        guard let tab, canSplit(tab) else { return nil }
        return tab
    }

    private func canSplit(_ tab: BrowserTab) -> Bool {
        guard !tab.isPrivate, tab.favoriteID == nil, tab.isPinned || tab.windowKey == windowKey,
              let scheme = tab.url?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
}
