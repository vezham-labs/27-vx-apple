import AppKit
import BrowserCore
import SwiftUI
import Suggest
import WebKit

struct RecentTabsPicker: View {
    @Environment(Browser.self) private var browser
    let tabs: [BrowserTab]
    let currentID: UUID?
    @State private var selected: UUID?
    @State private var previews: [UUID: NSImage] = [:]
    @FocusState private var pickerFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Tabs").font(.headline)

            ScrollViewReader { scroll in
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(tabs) { tab in
                            row(tab)
                        }
                    }
                }
                .frame(height: min(360, max(0, CGFloat(tabs.count) * 70 - 4)))
                .focusable()
                .focused($pickerFocused)
                .onMoveCommand { direction in
                    if direction == .up { moveSelection(by: -1) }
                    if direction == .down { moveSelection(by: 1) }
                }
                .onChange(of: selected) { _, id in
                    if let id { scroll.scrollTo(id) }
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { browser.isRecentTabsPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("Switch") { if let selected { browser.chooseRecentTab(selected) } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selected == nil)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear {
            selected = tabs.first(where: { $0.id != currentID })?.id ?? tabs.first?.id
            pickerFocused = true
        }
        .task(id: tabs.map(\.id)) { await loadPreviews() }
    }

    private func row(_ tab: BrowserTab) -> some View {
        Button { browser.chooseRecentTab(tab.id) } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(.quaternary)
                    if let preview = previews[tab.id] {
                        Image(nsImage: preview).resizable().scaledToFill()
                    } else {
                        TabIcon(tab: tab, size: 20)
                    }
                }
                .frame(width: 104, height: 54)
                .clipShape(.rect(cornerRadius: 6))
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(tab.displayTitle).fontWeight(.medium)
                    if let url = tab.url {
                        Text(URLNormalizer.displayHost(url))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)

                Spacer()
                if tab.id == currentID {
                    Text("Current").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(6)
            .background(selected == tab.id ? Color.accentColor.opacity(0.16) : .clear, in: .rect(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected == tab.id ? .isSelected : [])
        .id(tab.id)
    }

    private func moveSelection(by step: Int) {
        guard !tabs.isEmpty else { return }
        let position = tabs.firstIndex { $0.id == selected } ?? 0
        selected = tabs[(position + step + tabs.count) % tabs.count].id
    }

    private func loadPreviews() async {
        previews = [:]
        for tab in tabs {
            guard !Task.isCancelled else { return }
            guard !tab.isPrivate, let url = tab.url,
                  let view = browser.library.existingController(for: tab)?.page.view as? WKWebView,
                  !view.bounds.isEmpty else { continue }
            let bounds = view.bounds
            let configuration = WKSnapshotConfiguration()
            configuration.rect = CGRect(origin: bounds.origin,
                                        size: CGSize(width: bounds.width, height: min(bounds.height, bounds.width * 0.65)))
            configuration.snapshotWidth = NSNumber(value: min(192, bounds.width))
            let preview = try? await view.takeSnapshot(configuration: configuration)
            guard !Task.isCancelled else { return }
            if tab.url == url { previews[tab.id] = preview }
        }
    }
}
