#if os(macOS)
import AppKit
import WebKit
import BrowserEngine

/// Chrome's extension OAuth bridge. Only extensions that declared the identity permission can
/// start a flow, and a chromiumapp.org redirect is never sent to the network.
@available(macOS 15.4, *)
@MainActor
enum ExtensionAuth {
    static let bridgeName = "ark.identity"
    private static var flows: [String: Flow] = [:]

    nonisolated static func redirectOwner(_ url: URL?) -> String? {
        guard let url, url.scheme?.lowercased() == "https",
              let host = url.host()?.lowercased(), host.hasSuffix(".chromiumapp.org") else { return nil }
        let id = String(host.dropLast(".chromiumapp.org".count))
        return id.range(of: "^[a-p]{32}$", options: .regularExpression) != nil ? id : nil
    }

    nonisolated static func isChromiumAppURL(_ url: URL?) -> Bool {
        guard let host = url?.host()?.lowercased() else { return false }
        let normalized = host.hasSuffix(".") ? String(host.dropLast()) : host
        return normalized == "chromiumapp.org" || normalized.hasSuffix(".chromiumapp.org")
    }

    static func handle(_ body: [String: Any], extensionID: String, host: (any EngineExtensionHost)?,
                       reply: @escaping (Any?, (any Error)?) -> Void) {
        guard extensionID.hasPrefix("chrome:"),
              let urlText = body["url"] as? String, let url = URL(string: urlText),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            reply(nil, failure("Authorization page could not be loaded."))
            return
        }
        let id = String(extensionID.dropFirst("chrome:".count)).lowercased()
        guard id.range(of: "^[a-p]{32}$", options: .regularExpression) != nil else {
            reply(nil, failure("Sign-in is only available to Chrome Web Store extensions in Ark."))
            return
        }
        if flows[id] != nil { finish(id, with: .failure(failure("Another sign-in started."))) }

        if body["interactive"] as? Bool == true {
            guard let page = host?.openExtensionTab(url: url, windowID: nil, active: true) else {
                reply(nil, failure("Authorization page could not be loaded."))
                return
            }
            let flow = Flow(extensionID: id, reply: reply, page: page, host: host)
            flows[id] = flow
            flow.watchInteractive(timeout: 600)
        } else {
            let requested = (body["timeout"] as? Double ?? 5000) / 1000
            let timeout = min(max(requested, 0.5), 60)
            let dataStore = host?.extensionWindows.first(where: \.isFocused)?.activePage
                .flatMap { ($0 as? WebKitPage)?.webView.configuration.websiteDataStore } ?? .default()
            let flow = Flow(extensionID: id, reply: reply, host: host)
            flows[id] = flow
            flow.startQuiet(url, dataStore: dataStore, timeout: timeout)
        }
    }

    /// Claims a redirect from a tab that belongs to an active interactive flow.
    static func intercept(_ url: URL, from page: WebKitPage) -> Bool {
        guard isChromiumAppURL(url) else { return false }
        guard let id = redirectOwner(url), let flow = flows[id], flow.owns(page) else {
            return true
        }
        finish(id, with: .success(url))
        return true
    }

    static func registerPopup(from opener: WebKitPage, popup: any EnginePage) {
        guard let flow = flows.values.first(where: { $0.owns(opener) }) else { return }
        flow.popupPages.append(popup)
    }

    private static func finish(_ id: String, with result: Result<URL, Error>) {
        guard let flow = flows.removeValue(forKey: id) else { return }
        flow.stop()
        flow.popupPages.forEach { flow.host?.closeExtensionTab($0) }
        if let page = flow.page { flow.host?.closeExtensionTab(page) }
        switch result {
        case .success(let url): flow.reply(url.absoluteString, nil)
        case .failure(let error): flow.reply(nil, error)
        }
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "Ark.ExtensionAuth", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    @MainActor
    private final class Flow: NSObject, WKNavigationDelegate, WKUIDelegate {
        let extensionID: String
        let reply: (Any?, (any Error)?) -> Void
        weak var host: (any EngineExtensionHost)?
        let page: (any EnginePage)?
        var popupPages: [any EnginePage] = []
        private var view: WKWebView?
        private var timer: Task<Void, Never>?

        init(extensionID: String, reply: @escaping (Any?, (any Error)?) -> Void,
             page: (any EnginePage)? = nil, host: (any EngineExtensionHost)?) {
            self.extensionID = extensionID
            self.reply = reply
            self.page = page
            self.host = host
        }

        func startQuiet(_ url: URL, dataStore: WKWebsiteDataStore, timeout: TimeInterval) {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = dataStore
            configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
            configuration.mediaTypesRequiringUserActionForPlayback = .all
            let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
            view.navigationDelegate = self
            view.uiDelegate = self
            self.view = view
            timer = Task { [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                guard !Task.isCancelled, let self else { return }
                ExtensionAuth.finish(extensionID, with: .failure(ExtensionAuth.failure("User interaction required.")))
            }
            view.load(URLRequest(url: url))
        }

        func watchInteractive(timeout: TimeInterval) {
            timer = Task { [weak self] in
                guard let self else { return }
                for _ in 0..<Int(timeout) {
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled else { return }
                    let stillOpen = host?.extensionWindows.contains { window in
                        window.pages.contains { $0 === page }
                    } ?? false
                    guard stillOpen else {
                        ExtensionAuth.finish(extensionID, with: .failure(ExtensionAuth.failure("The user did not approve access.")))
                        return
                    }
                }
                ExtensionAuth.finish(extensionID, with: .failure(ExtensionAuth.failure("The user did not approve access.")))
            }
        }

        func stop() {
            timer?.cancel()
            timer = nil
            view?.stopLoading()
            view?.navigationDelegate = nil
            view?.uiDelegate = nil
            view = nil
        }

        func owns(_ page: any EnginePage) -> Bool {
            self.page === page || popupPages.contains { $0 === page }
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            let url = action.request.url
            if ExtensionAuth.isChromiumAppURL(url) {
                if action.targetFrame?.isMainFrame ?? true, let url,
                   ExtensionAuth.redirectOwner(url) == extensionID {
                    ExtensionAuth.finish(extensionID, with: .success(url))
                } else {
                    ExtensionAuth.finish(extensionID, with: .failure(ExtensionAuth.failure("Authorization page could not be loaded.")))
                }
                decisionHandler(.cancel)
                return
            }
            if action.targetFrame?.isMainFrame ?? true {
                guard ["http", "https"].contains(url?.scheme?.lowercased() ?? "") else {
                    ExtensionAuth.finish(extensionID, with: .failure(ExtensionAuth.failure("Authorization page could not be loaded.")))
                    decisionHandler(.cancel)
                    return
                }
            } else if !["http", "https", "about", "data", "blob"].contains(url?.scheme?.lowercased() ?? "") {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }
        func webView(_ webView: WKWebView, decideMediaCapturePermissionsFor origin: WKSecurityOrigin,
                     initiatedBy frame: WKFrameInfo, type: WKMediaCaptureType) async -> WKPermissionDecision { .deny }
        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo) async {}
        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo) async -> Bool { false }
        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                     defaultText: String?, initiatedByFrame frame: WKFrameInfo) async -> String? { nil }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            failNavigation(error)
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            failNavigation(error)
        }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            ExtensionAuth.finish(extensionID, with: .failure(ExtensionAuth.failure("Authorization page could not be loaded.")))
        }
        private func failNavigation(_ error: Error) {
            let error = error as NSError
            if error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled { return }
            ExtensionAuth.finish(extensionID, with: .failure(ExtensionAuth.failure("Authorization page could not be loaded.")))
        }
    }
}
#endif
