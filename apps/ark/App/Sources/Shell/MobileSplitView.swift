import SwiftUI
import BrowserCore

struct MobileSplitView<Page: View>: View {
    @Environment(BrowserState.self) private var browser
    @GestureState private var dragOffset: CGFloat = 0
    let first: BrowserTab
    let second: BrowserTab
    @ViewBuilder var page: (BrowserTab) -> Page

    var body: some View {
        GeometryReader { geometry in
            let sideBySide = geometry.size.width >= 620
            let length = sideBySide ? geometry.size.width : geometry.size.height
            let available = max(1, length - 18)
            let fraction = browser.currentSpace.splitPair?.fraction ?? 0.5
            let current = min(0.75, max(0.25, fraction + dragOffset / available))
            if sideBySide {
                HStack(spacing: 0) {
                    pane(first).frame(width: available * current)
                    divider(sideBySide: true, length: available, fraction: fraction)
                    pane(second)
                }
            } else {
                VStack(spacing: 0) {
                    pane(first).frame(height: available * current)
                    divider(sideBySide: false, length: available, fraction: fraction)
                    pane(second)
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

    private func divider(sideBySide: Bool, length: CGFloat, fraction: Double) -> some View {
        Color(.systemGroupedBackground)
            .overlay {
                Capsule()
                    .fill(.secondary.opacity(0.5))
                    .frame(width: sideBySide ? 3 : 32, height: sideBySide ? 32 : 3)
            }
            .frame(width: sideBySide ? 18 : nil, height: sideBySide ? nil : 18)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .global)
                .updating($dragOffset) { gesture, offset, _ in
                    offset = sideBySide ? gesture.translation.width : gesture.translation.height
                }
                .onEnded { gesture in
                    let offset = sideBySide ? gesture.translation.width : gesture.translation.height
                    updateSplit(to: fraction + offset / length)
                })
            .accessibilityLabel("Split Divider")
            .accessibilityValue(Text(fraction.formatted(.percent.precision(.fractionLength(0)))))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: updateSplit(to: fraction + 0.1)
                case .decrement: updateSplit(to: fraction - 0.1)
                @unknown default: break
                }
            }
    }

    private func updateSplit(to fraction: Double) {
        browser.currentSpace.resizeSplit(to: fraction)
        browser.scheduleSave()
    }
}
