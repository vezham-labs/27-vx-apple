import Foundation
import WebKit

public struct HiddenSiteElement: Codable, Identifiable, Equatable, Sendable {
    public var selector: String
    public var label: String
    public var note: String?
    public var date: Date

    public var id: String { selector }

    public init(selector: String, label: String, note: String? = nil, date: Date = .now) {
        self.selector = selector
        self.label = label
        self.note = note
        self.date = date
    }
}

@MainActor
public final class SiteStyles {
    private let fileURL: URL?
    private let hiddenFileURL: URL?
    private var styles: [String: String]
    private var hidden: [String: [HiddenSiteElement]]
    private var revision = 0

    public init(fileURL: URL?) {
        self.fileURL = fileURL
        hiddenFileURL = fileURL?.deletingLastPathComponent().appending(path: "site-hidden-elements.json")
        styles = fileURL.flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        if let data = hiddenFileURL.flatMap({ try? Data(contentsOf: $0) }),
           let decoded = try? JSONDecoder().decode([String: [HiddenSiteElement]].self, from: data) {
            hidden = decoded
        } else if let data = hiddenFileURL.flatMap({ try? Data(contentsOf: $0) }),
                  let legacy = try? JSONDecoder().decode([String: [String]].self, from: data) {
            hidden = legacy.mapValues { $0.map { HiddenSiteElement(selector: $0, label: $0) } }
        } else {
            hidden = [:]
        }
    }

    public subscript(host: String) -> String? { styles[host] }

    public func hiddenElements(for host: String) -> [HiddenSiteElement] { hidden[host] ?? [] }

    public func hiddenSelectors(for host: String) -> [String] { hiddenElements(for: host).map(\.selector) }

    public func hasStyle(for host: String) -> Bool { styles[host] != nil || hidden[host] != nil }

    public func hide(_ selector: String, for host: String) throws {
        try hide(HiddenSiteElement(selector: selector, label: selector), for: host)
    }

    public func hide(_ element: HiddenSiteElement, for host: String) throws {
        let elements = hiddenElements(for: host)
        guard !element.selector.isEmpty, !elements.contains(where: { $0.selector == element.selector }) else { return }
        try setHidden(elements + [element], for: host)
    }

    public func restore(_ selector: String, for host: String) throws {
        try setHidden(hiddenElements(for: host).filter { $0.selector != selector }, for: host)
    }

    public func restoreAll(for host: String) throws {
        try setHidden([], for: host)
    }

    private func setHidden(_ elements: [HiddenSiteElement], for host: String) throws {
        guard elements != hiddenElements(for: host) else { return }
        var updated = hidden
        updated[host] = elements.isEmpty ? nil : elements
        if let hiddenFileURL {
            try FileManager.default.createDirectory(at: hiddenFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(updated).write(to: hiddenFileURL, options: .atomic)
        }
        hidden = updated
        revision += 1
    }

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
        await apply(to: webView, on: host, includingRemoval: includingRemoval, showing: nil)
    }

    /// Applies the style with one saved element revealed, outlined, and scrolled into view for preview.
    public func apply(to webView: WKWebView, on host: String, includingRemoval: Bool = false,
                      showing selectorToShow: String?) async {
        guard Self.host(of: webView.url) == host, hasStyle(for: host) || includingRemoval else { return }
        let css = styles[host] ?? ""
        revision += 1
        let applyRevision = revision
        let selectors = hiddenSelectors(for: host).filter { $0 != selectorToShow }
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
            if (!css && hidden.length === 0) {
                if (sheet) document.adoptedStyleSheets = document.adoptedStyleSheets.filter(item => !isArkSheet(item));
                globalThis.arkSiteStyle = { revision };
                return;
            }
            const installed = Boolean(sheet);
            sheet ??= new CSSStyleSheet();
            if (!installed || state?.revision !== revision) {
                sheet.replaceSync(css);
                for (const selector of hidden) {
                    try { sheet.insertRule(`${selector} { display: none !important; }`, sheet.cssRules.length); } catch {}
                }
                if (showing) {
                    try { sheet.insertRule(`:is(${showing}):not(#ark-preview):not(#ark-preview):not(#ark-preview) { outline: 2px solid rgba(23, 23, 23, .9) !important; outline-offset: 2px !important; }`, sheet.cssRules.length); } catch {}
                }
                sheet.insertRule(':root { --ark-site-style: 1; }', sheet.cssRules.length);
            }
            if (!installed) document.adoptedStyleSheets = [...document.adoptedStyleSheets, sheet];
            globalThis.arkSiteStyle = { revision };
            if (showing) {
                try { document.querySelector(showing)?.scrollIntoView({ block: 'center', behavior: 'smooth' }); } catch {}
            }
            """, arguments: ["host": host, "css": css, "hidden": selectors, "showing": selectorToShow as Any? ?? NSNull(),
                             "revision": applyRevision], in: nil,
            contentWorld: .world(name: "ark.site-style"))
    }
}
