import Foundation
import WebKit

@MainActor
public final class SiteStyles {
    private let fileURL: URL?
    private var styles: [String: String]
    private var revision = 0

    public init(fileURL: URL?) {
        self.fileURL = fileURL
        styles = fileURL.flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
    }

    public subscript(host: String) -> String? { styles[host] }

    public static func host(of url: URL?) -> String? {
        guard let url, let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", let host = url.host(percentEncoded: true)?.lowercased(),
              !host.isEmpty else { return nil }
        return host
    }

    public func set(_ css: String, for host: String) throws {
        let value = css.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : css
        guard styles[host] != value else { return }
        var updated = styles
        updated[host] = value
        if let fileURL {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(updated).write(to: fileURL, options: .atomic)
        }
        styles = updated
        revision += 1
    }

    public func apply(to webView: WKWebView, on host: String, includingRemoval: Bool = false) async {
        guard Self.host(of: webView.url) == host, styles[host] != nil || includingRemoval else { return }
        let css = styles[host] ?? ""
        // WebKit can expose different wrappers for an adopted sheet on later calls.
        // Identify our sheet by its final rule and keep the save revision in the isolated world.
        _ = try? await webView.callAsyncJavaScript("""
            if (!['http:', 'https:'].includes(location.protocol) || location.hostname !== host) return;
            const state = globalThis.arkSiteStyle;
            if (state && state.revision > revision) return;
            const marker = '--ark-site-style';
            const isArkSheet = item => {
                const rule = item.cssRules[item.cssRules.length - 1];
                return rule?.selectorText === ':root' && rule.style.getPropertyValue(marker).trim() === '1';
            };
            let sheet = document.adoptedStyleSheets.find(isArkSheet);
            if (!css) {
                if (sheet) document.adoptedStyleSheets = document.adoptedStyleSheets.filter(item => !isArkSheet(item));
                globalThis.arkSiteStyle = { revision };
                return;
            }
            const installed = Boolean(sheet);
            sheet ??= new CSSStyleSheet();
            if (!installed || state?.css !== css) {
                sheet.replaceSync(css);
                sheet.insertRule(':root { --ark-site-style: 1; }', sheet.cssRules.length);
            }
            if (!installed) document.adoptedStyleSheets = [...document.adoptedStyleSheets, sheet];
            globalThis.arkSiteStyle = { css, revision };
            """, arguments: ["host": host, "css": css, "revision": revision], in: nil,
            contentWorld: .world(name: "ark.site-style"))
    }
}
