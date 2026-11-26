import SwiftUI
import BrowserCore

struct SplitPageView: View {
    @Environment(Browser.self) private var browser
    @GestureState private var drag: DividerDrag?
    let split: TabSplit
    let tabs: [BrowserTab]

    private struct DividerDrag {
        let index: Int
        let distance: CGFloat
    }

    var body: some View {
        GeometryReader { geometry in
            let horizontal = split.axis == .sideBySide
            let layout = horizontal ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
            let length = max(1, (horizontal ? geometry.size.width : geometry.size.height) - CGFloat(tabs.count - 1) * 8)
            let shares = drag.map { split.resizedShares(after: $0.index, by: $0.distance / length) } ?? split.shares
            layout {
                ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                    let paneLength = shares[index] * length
                    pane(tab).frame(width: horizontal ? paneLength : nil, height: horizontal ? nil : paneLength)
                    if index < tabs.count - 1 { divider(after: index, horizontal: horizontal, length: length) }
                }
            }
        }
    }

    private func pane(_ tab: BrowserTab) -> some View {
        let focused = browser.currentTab?.id == tab.id
        return VStack(spacing: 0) {
            HStack {
                Button {
                    browser.focusSplitPane(tab)
                } label: {
                    Text(tab.displayTitle)
                        .font(.caption.weight(focused ? .semibold : .regular))
                        .lineLimit(1)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(focused ? .isSelected : [])
                Menu {
                        let index = split.tabs.firstIndex(of: tab.id) ?? 0
                        Button(split.axis == .sideBySide ? "Move Left" : "Move Up") { browser.moveSplitPane(tab, by: -1) }
                            .disabled(index == 0)
                        Button(split.axis == .sideBySide ? "Move Right" : "Move Down") { browser.moveSplitPane(tab, by: 1) }
                            .disabled(index == split.tabs.count - 1)
                        Button("Remove from Split View") { browser.removeSplitPane(tab) }
                        Button("Close Tab") { browser.close(tab) }
                        Divider()
                        Button("Side by Side") { browser.setSplitAxis(.sideBySide) }
                        Button("Stacked") { browser.setSplitAxis(.stacked) }
                        Button("Equal Panes") { browser.equaliseSplit() }
                        let candidates = browser.additionalSplitCandidates
                        if !candidates.isEmpty {
                            Menu("Add Pane") {
                                ForEach(candidates) { other in
                                    Button(other.displayTitle) { browser.addToSplit(other) }
                                }
                            }
                        }
                        Button("Separate Tabs") { browser.separateSplit() }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .menuStyle(.borderlessButton)
                    .accessibilityLabel("Split View Options")
                    .fixedSize()
            }
            .padding(.horizontal, 8)
            .background(focused ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
            ZStack(alignment: .top) {
                if focused, let reader = browser.reader, browser.isReaderShowing {
                    PageHost(view: reader.page.view, focusesPage: browser.commandBar == nil && browser.find == nil)
                } else {
                    PageHost(view: browser.controller(for: tab).page.view,
                             focusesPage: focused && browser.commandBar == nil && browser.find == nil && browser.glance == nil,
                             onClick: { browser.focusSplitPane(tab) })
                    if let server = RadarStore.shared.server(for: tab.url), !server.isUp {
                        RadarStoppedPage(server: server)
                    } else if let error = tab.loadError {
                        ErrorPage(error: error, handlesReturn: focused, retry: {
                            browser.focusSplitPane(tab)
                            browser.reload()
                        }, goBack: {
                            browser.focusSplitPane(tab)
                            browser.goBack()
                        })
                    } else {
                        ProgressLine(isLoading: tab.isLoading, progress: tab.estimatedProgress)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .clipShape(.rect(cornerRadius: PageCard.radius))
    }

    private func divider(after index: Int, horizontal: Bool, length: CGFloat) -> some View {
        Rectangle()
            .fill(.clear)
            .contentShape(Rectangle())
            .overlay {
                Capsule().fill(.secondary.opacity(0.45))
                    .frame(width: horizontal ? 2 : 24, height: horizontal ? 24 : 2)
            }
            .frame(width: horizontal ? 8 : nil, height: horizontal ? nil : 8)
            .frame(maxWidth: horizontal ? nil : .infinity, maxHeight: horizontal ? .infinity : nil)
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .updating($drag) { value, state, _ in
                    state = DividerDrag(index: index, distance: horizontal ? value.translation.width : value.translation.height)
                }
                .onEnded { value in
                    let delta = horizontal ? value.translation.width : value.translation.height
                    browser.resizeSplit(after: index, by: delta / length)
                })
            .accessibilityLabel("Split Divider \(index + 1)")
            .accessibilityValue("\(Int(split.shares[index] * 100)) percent")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: browser.resizeSplit(after: index, by: 0.05)
                case .decrement: browser.resizeSplit(after: index, by: -0.05)
                @unknown default: break
                }
            }
    }
}

struct SplitTabPicker: View {
    @Environment(Browser.self) private var browser
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Split View").font(.headline)
            if browser.splitCandidates.isEmpty {
                Text("Open another web tab in this Space to use Split View.")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(browser.splitCandidates) { tab in
                            Button { browser.splitWith(tab) } label: {
                                Label(tab.displayTitle, systemImage: "rectangle.split.2x1")
                                    .lineLimit(1)
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(20)
        .frame(width: 380)
    }
}
