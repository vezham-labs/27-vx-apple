import SwiftUI
import BrowserCore

private struct PinnedTabDragDrop: ViewModifier {
    let tab: BrowserTab
    let space: Space
    let browser: BrowserState
    let save: () -> Void
    @State private var size = CGSize(width: 60, height: 44)

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            .draggable(PinFolderDragItem.pin(tab.id)) { content }
            .dropDestination(for: String.self) { items, location in
                guard let value = items.first else { return false }
                let moved: Bool
                if let pinID = PinFolderDragItem.pinID(value) {
                    moved = space.movePinnedTab(pinID, into: tab.pinFolderID, relativeTo: tab.id,
                                                after: location.x >= size.width / 2)
                } else if let folderID = PinFolderDragItem.folderID(value) {
                    moved = space.movePinFolder(folderID, into: tab.pinFolderID)
                } else if let todayID = UUID(uuidString: value) {
                    moved = browser.moveTodayTabToPinned(todayID, in: space, into: tab.pinFolderID,
                                                         relativeTo: tab.id, after: location.x >= size.width / 2)
                } else {
                    moved = false
                }
                if moved { save() }
                return moved
            }
    }
}

extension View {
    func pinnedTabDragDrop(_ tab: BrowserTab, in space: Space, browser: BrowserState,
                           save: @escaping () -> Void) -> some View {
        modifier(PinnedTabDragDrop(tab: tab, space: space, browser: browser, save: save))
    }
}
