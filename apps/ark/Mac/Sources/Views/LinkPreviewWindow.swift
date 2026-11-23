import AppKit
import BrowserCore
import BrowserEngine
import SwiftUI

@MainActor
final class LinkPreviewWindow: NSWindowController, NSWindowDelegate {
    let controller: TabController
    var tab: BrowserTab { controller.tab }
    private weak var library: Library?
    private let destination: UUID?
    private var kept = false
    private var keyMonitor: Any?

    static func supports(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased() ?? "") && url.host() != nil
    }

    init(url: URL?, library: Library, popup: (any EnginePage)? = nil) {
        self.library = library
        destination = SpaceRouter.shared.space(for: url, in: library)?.id ?? library.settings.externalLinksSpaceID
        let tab = BrowserTab(url: popup == nil ? nil : url)
        controller = TabController(tab: tab, library: library) { delegate in
            popup ?? library.engine.makePage(options: PageOptions(profile: .standard), delegate: delegate)
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 540),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Link Preview"
        window.tabbingMode = .disallowed
        window.minSize = NSSize(width: 360, height: 300)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.center()
        window.contentView = NSHostingView(rootView: LinkPreviewContent(tab: tab, page: controller.page) { [weak self] in
            self?.keep()
        })
        controller.linkPreview = self
        if popup == nil, let url { controller.load(url, source: .link) }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let consumed = MainActor.assumeIsolated { self?.handleKey(event) ?? false }
            return consumed ? nil : event
        }
    }

    required init?(coder: NSCoder) { nil }

    func keep() {
        guard !kept, let library else { return }
        kept = true
        controller.linkPreview = nil
        close()
        library.keepLinkPreview(controller, destination: destination)
    }

    func windowWillClose(_ notification: Notification) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if !kept { controller.page.close() }
        library?.linkWindows[tab.id] = nil
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard let window, event.window === window, window.attachedSheet == nil else { return false }
        if event.keyCode == 53 { close(); return true }
        if event.keyCode == 36, event.modifierFlags.contains(.command) { keep(); return true }
        return false
    }
}

private struct LinkPreviewContent: View {
    let tab: BrowserTab
    let page: any EnginePage
    let keep: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                TabIcon(tab: tab)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tab.displayTitle).font(.callout.weight(.medium))
                    if let host = tab.url?.host() {
                        Text(host).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
                Spacer()
                Button("Open as Tab", systemImage: "arrow.up.right", action: keep)
                    .help("Open as Tab (⌘Return)")
            }
            .padding(12)
            .background(PanelFill())
            PageHost(view: page.view, focusesPage: true)
                .overlay(alignment: .top) {
                    ProgressLine(isLoading: tab.isLoading, progress: tab.estimatedProgress)
                }
                .overlay {
                    if let error = tab.loadError {
                        ErrorPage(error: error, retry: { page.reload() }, goBack: { page.goBack() })
                    }
                }
                .padding(6)
        }
    }
}
