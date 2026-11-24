import SwiftUI
import BrowserCore

struct PageCapturePicker: View {
    let mode: BrowserState.PageSelectionMode
    let topInset: CGFloat
    let bottomInset: CGFloat
    let cancel: () -> Void
    let copy: (CGRect) -> Void
    let copyElement: (CGPoint) -> Void
    @State private var selection = CGRect.null

    var body: some View {
        GeometryReader { geometry in
            let viewport = CGRect(origin: .zero, size: geometry.size)
            let top = max(geometry.safeAreaInsets.top, topInset)
            let bottom = max(geometry.safeAreaInsets.bottom, bottomInset)
            let available = CGRect(x: 0, y: top, width: viewport.width,
                                   height: max(0, viewport.height - top - bottom))
            let region = selection.intersection(available)
            ZStack(alignment: .top) {
                Path { path in
                    path.addRect(viewport)
                    if !region.isEmpty { path.addRect(region) }
                }
                .fill(.black.opacity(0.40), style: FillStyle(eoFill: true))
                .overlay {
                    if !region.isEmpty {
                        Rectangle().stroke(.white, lineWidth: 1)
                            .frame(width: region.width, height: region.height)
                            .position(x: region.midX, y: region.midY)
                            .allowsHitTesting(false)
                    }
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 3).onChanged { value in
                    guard mode == .area, available.contains(value.startLocation) else { return }
                    let start = value.startLocation
                    let end = value.location
                    selection = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                                       width: abs(start.x - end.x), height: abs(start.y - end.y))
                })
                .simultaneousGesture(SpatialTapGesture().onEnded { value in
                    if mode != .area, available.contains(value.location) { copyElement(value.location) }
                })
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(mode == .area ? "Page area selection" : "Page element selection")
                .accessibilityIdentifier("page-capture-surface")
                .accessibilityActions {
                    if mode == .area {
                        Button("Select Visible Area") { selection = available }
                    }
                }

                VStack(spacing: 4) {
                    HStack {
                        Button("Cancel", action: cancel)
                            .keyboardShortcut(.escape, modifiers: [])
                        Spacer()
                        if mode == .area {
                            Button("Copy Area") { copy(region) }
                                .disabled(region.width < 2 || region.height < 2)
                                .fontWeight(.semibold)
                        }
                    }
                        Text(mode == .area ? "Drag to select an area" : mode == .hideElement ? "Tap an element to hide it on this site" : "Tap an element to copy it")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: 360)
                .background(.regularMaterial, in: .rect(cornerRadius: 16))
                .padding(.horizontal, 16)
                .padding(.top, top + 8)
            }
            .onChange(of: geometry.size) { selection = .null }
        }
    }
}
