import SwiftUI
import BrowserCore

struct MobileSplitView<Page: View>: View {
    @Environment(BrowserState.self) private var browser
    @GestureState private var drag: DividerDrag?
    let split: TabSplitPair
    let members: [BrowserTab]
    @ViewBuilder var page: (BrowserTab) -> Page

    private struct DividerDrag {
        let index: Int
        let distance: CGFloat
    }

    var body: some View {
        GeometryReader { geometry in
            let sideBySide = geometry.size.width >= 620
            let length = sideBySide ? geometry.size.width : geometry.size.height
            let available = max(1, length - CGFloat(members.count - 1) * 18)
            let shares = drag.map { split.resizedShares(after: $0.index, by: $0.distance / available) } ?? split.shares
            let layout = sideBySide ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
            layout {
                ForEach(Array(members.enumerated()), id: \.element.id) { index, tab in
                    pane(tab).frame(width: sideBySide ? available * shares[index] : nil,
                                    height: sideBySide ? nil : available * shares[index])
                    if index < members.count - 1 {
                        divider(after: index, sideBySide: sideBySide, length: available)
                    }
                }
            }
        }
    }

    private func pane(_ tab: BrowserTab) -> some View {
        let selected = tab.id == browser.currentTab?.id
        return VStack(spacing: 0) {
            Button {
                browser.focusSplitPane(tab)
            } label: {
                Label(tab.displayTitle, systemImage: selected ? "checkmark.circle.fill" : "circle")
                    .font(.subheadline.weight(selected ? .semibold : .regular))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.horizontal, 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Color(.secondarySystemGroupedBackground))
            .accessibilityIdentifier("split-pane-\(tab.displayTitle)")
            .accessibilityAddTraits(selected ? [.isSelected] : [])
            page(tab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        }
        .background(Color(.systemBackground))
        .clipped()
    }

    private func divider(after index: Int, sideBySide: Bool, length: CGFloat) -> some View {
        Color(.systemGroupedBackground)
            .overlay {
                Capsule()
                    .fill(.secondary.opacity(0.5))
                    .frame(width: sideBySide ? 3 : 32, height: sideBySide ? 32 : 3)
            }
            .frame(width: sideBySide ? 18 : nil, height: sideBySide ? nil : 18)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .global)
                .updating($drag) { gesture, state, _ in
                    let distance = sideBySide ? gesture.translation.width : gesture.translation.height
                    state = DividerDrag(index: index, distance: distance)
                }
                .onEnded { gesture in
                    let offset = sideBySide ? gesture.translation.width : gesture.translation.height
                    updateSplit(after: index, by: offset / length)
                })
            .accessibilityLabel("Split Divider \(index + 1)")
            .accessibilityValue(Text(split.shares[index].formatted(.percent.precision(.fractionLength(0)))))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: updateSplit(after: index, by: 0.05)
                case .decrement: updateSplit(after: index, by: -0.05)
                @unknown default: break
                }
            }
    }

    private func updateSplit(after index: Int, by delta: Double) {
        browser.currentSpace.resizeSplit(after: index, by: delta)
        browser.scheduleSave()
    }
}
