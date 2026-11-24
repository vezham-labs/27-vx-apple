import SwiftUI
import AppKit
import BrowserCore
import BrowserEngine

/// Glance: a configured modified click previews a link in a card over the page, like Zen's Glance and Arc's
/// Peek. Esc (or a click outside) puts it away; ⌘Return or the expand button makes it a tab.
@MainActor @Observable
final class GlanceSession: Identifiable, EnginePageDelegate {
    let id = UUID()
    let page: any EnginePage
    let profile: BrowsingProfile
    var isPrivate: Bool { profile == .ephemeral }
    @ObservationIgnored private(set) var loadedURL: URL?
    @ObservationIgnored weak var browser: Browser?

    init(url: URL, profile: BrowsingProfile, browser: Browser) {
        self.profile = profile
        self.browser = browser
        page = browser.engine.makePage(options: PageOptions(profile: profile, url: url),
                                       delegate: GlanceSession.placeholder)
        page.delegate = self
    }

    /// makePage needs a delegate before `self` exists.
    private static let placeholder = PlaceholderDelegate()
    private final class PlaceholderDelegate: EnginePageDelegate {}

    var url: URL? { page.state.url }

    // Links inside the Glance stay in it; new windows become tabs.
    func page(_ page: any EnginePage, decide request: NavigationRequest) async -> NavigationDecision {
        if request.wantsNewTab {
            browser?.newTab(url: request.url, isPrivate: isPrivate, source: .link, select: request.wantsForeground)
            return .cancel
        }
        return .allow
    }

    func page(_ page: any EnginePage, didCommit url: URL?) {
        loadedURL = nil
        browser?.cancelPrompts(for: id)
    }
    func page(_ page: any EnginePage, didFinish url: URL, title: String) { loadedURL = url }
    func page(_ page: any EnginePage, didFailWith error: NSError) { loadedURL = nil }
    func pageContentProcessDidTerminate(_ page: any EnginePage) { loadedURL = nil }

    func page(_ page: any EnginePage, requestPermission permission: EnginePermission, host: String) async -> Bool {
        guard permission == .screen, let browser else { return false }
        return await browser.askFromGlance(.permission(permission, host: host), glance: self) == .ok
    }

    func page(_ page: any EnginePage, openedPopup popup: any EnginePage, url: URL?) -> (any EnginePageDelegate)? {
        if let url { browser?.newTab(url: url, isPrivate: isPrivate, source: .link) }
        return nil
    }

    func pageDidRequestClose(_ page: any EnginePage) { browser?.closeGlance() }

    /// Blocking already applies (same rules as tabs); say so when a cookie banner goes, as tabs do.
    func pageDidDeclineCookieBanner(_ page: any EnginePage) {
        browser?.showToast("Cookie banner declined")
    }
}

extension Browser {
    static func canPreviewLink(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), url.host() != nil else { return false }
        return scheme == "http" || scheme == "https"
    }

    @discardableResult
    func previewLink(_ url: URL, from tab: BrowserTab?) -> Bool {
        guard Self.canPreviewLink(url) else { return false }
        let profile = tab.map(library.browsingProfile(for:)) ?? library.browsingProfile(in: currentSpace)
        commandBar = nil
        openGlance(url, profile: profile)
        return true
    }

    func openGlance(_ url: URL, profile: BrowsingProfile) {
        closeGlance()
        glance = GlanceSession(url: url, profile: profile, browser: self)
    }

    func closeGlance() {
        guard let glance else { return }
        cancelPrompts(for: glance.id)
        glance.page.close()
        self.glance = nil
    }

    /// Keeps the live document when the destination uses the same website profile and engine.
    func expandGlance() {
        guard let glance else { return }
        guard let url = glance.url else { return closeGlance() }
        cancelPrompts(for: glance.id)
        self.glance = nil
        newTab(url: url, isPrivate: glance.isPrivate, source: .link, promoting: glance)
    }

    var canExpandGlanceInSplit: Bool {
        guard let glance, let url = glance.url, Self.canPreviewLink(url), canAddSplitPane else { return false }
        return glance.profile == library.browsingProfile(in: currentSpace)
    }

    func expandGlanceInSplit() {
        guard canExpandGlanceInSplit, let glance, let url = glance.url else { return }
        cancelPrompts(for: glance.id)
        let addingPane = activeSplit != nil
        // Release the overlay's host as the pane takes over the same view.
        var transition = Transaction(animation: nil)
        transition.disablesAnimations = true
        withTransaction(transition) {
            self.glance = nil
            glance.page.view.removeFromSuperview()
            let tab = newTab(url: url, in: currentSpace, source: .link, select: false, promoting: glance)
            // The URL of a still-loading preview may not have reached the new tab yet.
            if tab.url == nil { tab.url = url }
            if addingPane { addToSplit(tab) } else { splitWith(tab) }
            focusSplitPane(tab)
        }
    }
}

struct PreviewLinkButton: View {
    @Environment(Browser.self) private var browser
    let url: URL
    var tab: BrowserTab? = nil

    var body: some View {
        if Browser.canPreviewLink(url) {
            Button("Preview Link", systemImage: "rectangle.inset.filled") { browser.previewLink(url, from: tab) }
        }
    }
}

struct GlanceOverlay: View {
    @Environment(Browser.self) private var browser
    let glance: GlanceSession
    @State private var monitor: Any?

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .contentShape(.rect)
                .onTapGesture { browser.closeGlance() }
            VStack(spacing: 0) {
                header
                PageHost(view: glance.page.view, focusesPage: true, shouldHost: { browser.glance === glance })
                    .overlay(alignment: .top) {
                        // The same hairline as a tab's, under the header.
                        ProgressLine(isLoading: glance.page.state.isLoading, progress: glance.page.state.progress)
                    }
            }
            .clipShape(.rect(cornerRadius: 14, style: .continuous))
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
                    .shadow(color: .black.opacity(0.3), radius: 24, y: 10)
            }
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.primary.opacity(0.08)))
            .padding(.horizontal, 44)
            .padding(.vertical, 28)
        }
        // The dimming stays inside the page card's rounded corners.
        .clipShape(.rect(cornerRadius: PageCard.radius, style: .continuous))
        .onAppear(perform: watchKeys)
        .onDisappear {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            if let url = glance.url { FaviconView(url: url, size: 14) }
            VStack(alignment: .leading, spacing: 0) {
                Text(glance.page.state.title.isEmpty ? "Loading…" : glance.page.state.title)
                    .font(.callout.weight(.medium)).lineLimit(1)
                if let host = glance.url?.host() {
                    Text(host).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            if browser.canExpandGlanceInSplit {
                Button { browser.expandGlanceInSplit() } label: {
                    Image(systemName: "rectangle.split.2x1")
                }
                .accessibilityLabel("Open in Split View")
                .help("Open in Split View (⌥⌘Return)")
            }
            Button { browser.expandGlance() } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .help("Open as a Tab (⌘Return)")
            Button { browser.closeGlance() } label: { Image(systemName: "xmark") }
                .help("Close (Esc)")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(PanelFill())
        .overlay(alignment: .bottom) { Divider().opacity(0.5) }
    }

    /// Esc closes, ⌘Return keeps it as a tab, while this window is key.
    private func watchKeys() {
        let window = browser.nsWindow
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.window === window else { return event }
            if event.keyCode == 53 {
                MainActor.assumeIsolated { browser.closeGlance() }
                return nil
            }
            if event.keyCode == 36, event.modifierFlags.contains(.command) {
                if event.modifierFlags.contains(.option) {
                    let handled = MainActor.assumeIsolated {
                        guard browser.canExpandGlanceInSplit else { return false }
                        browser.expandGlanceInSplit()
                        return true
                    }
                    return handled ? nil : event
                }
                MainActor.assumeIsolated { browser.expandGlance() }
                return nil
            }
            return event
        }
    }
}
