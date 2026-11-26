import Foundation
import WebKit

public struct HiddenSiteElement: Codable, Identifiable, Equatable, Sendable {
    public struct Shape: Codable, Equatable, Sendable {
        public var width: Double?
        public var height: Double?
        public var dx: Double?
        public var dy: Double?

        public init(width: Double? = nil, height: Double? = nil, dx: Double? = nil, dy: Double? = nil) {
            self.width = width; self.height = height; self.dx = dx; self.dy = dy
        }

        fileprivate var valid: Bool {
            [width, height].allSatisfy { $0.map { $0.isFinite && (1...20_000).contains($0) } ?? true }
                && [dx, dy].allSatisfy { $0.map { $0.isFinite && (-20_000...20_000).contains($0) } ?? true }
                && [width, height, dx, dy].contains { $0 != nil }
        }
    }
    public var selector: String
    public var label: String
    public var note: String?
    /// A small description of an element selected by position.  When a page
    /// rearranges its content, Ark checks this before hiding that position.
    /// Older Boosts deliberately leave this nil and retain their CSS behavior.
    public var fingerprint: String?
    /// A stable class-based place to look when the original path moved.
    public var family: String?
    /// Nil means hidden. A shape changes only the matched element's presentation.
    public var shape: Shape?
    public var date: Date

    public var id: String { selector }

    public init(selector: String, label: String, note: String? = nil, fingerprint: String? = nil,
                family: String? = nil, date: Date = .now) {
        self.selector = selector
        self.label = label
        self.note = note
        self.fingerprint = fingerprint
        self.family = family
        self.date = date
    }

    /// A deterministic, CSS-safe marker for a guarded page element.
    public var guardKey: String {
        var hash: UInt32 = 2_166_136_261
        for byte in (selector + "\n" + (fingerprint ?? "")).utf8 {
            hash = (hash ^ UInt32(byte)) &* 16_777_619
        }
        return "ark-" + String(hash, radix: 36)
    }
}

/// The portable, inspectable representation of one Ark Boost.
/// It deliberately contains only page presentation rules—never cookies, history, or account data.
public struct SharedSiteStyle: Codable, Sendable {
    public let arkBoost: Int
    public let host: String
    public let css: String?
    public let font: SiteStyleFont
    public let accent: String?
    public let hiddenElements: [HiddenSiteElement]

    public init(arkBoost: Int = 1, host: String, css: String?, font: SiteStyleFont,
                accent: String?, hiddenElements: [HiddenSiteElement]) {
        self.arkBoost = arkBoost
        self.host = host
        self.css = css
        self.font = font
        self.accent = accent
        self.hiddenElements = hiddenElements
    }
}

public enum SiteStyleFont: String, Codable, CaseIterable, Identifiable, Sendable {
    case original
    case system
    case serif
    case rounded
    case mono

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .original: "Original"
        case .system: "System"
        case .serif: "Serif"
        case .rounded: "Rounded"
        case .mono: "Mono"
        }
    }

    fileprivate var css: String? {
        switch self {
        case .original: nil
        case .system: "-apple-system, BlinkMacSystemFont, 'SF Pro Text', sans-serif"
        case .serif: "'New York', ui-serif, Georgia, serif"
        case .rounded: "ui-rounded, 'SF Pro Rounded', -apple-system, sans-serif"
        case .mono: "ui-monospace, 'SF Mono', Menlo, monospace"
        }
    }
}

@MainActor
public final class SiteStyles {
    private let fileURL: URL?
    private let hiddenFileURL: URL?
    private let fontsFileURL: URL?
    private let accentsFileURL: URL?
    private var styles: [String: String]
    private var hidden: [String: [HiddenSiteElement]]
    private var fonts: [String: SiteStyleFont]
    private var accents: [String: String]
    private var revision = 0

    public init(fileURL: URL?) {
        self.fileURL = fileURL
        hiddenFileURL = fileURL?.deletingLastPathComponent().appending(path: "site-hidden-elements.json")
        fontsFileURL = fileURL?.deletingLastPathComponent().appending(path: "site-fonts.json")
        accentsFileURL = fileURL?.deletingLastPathComponent().appending(path: "site-accents.json")
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
        fonts = fontsFileURL.flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode([String: SiteStyleFont].self, from: $0) } ?? [:]
        accents = accentsFileURL.flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
    }

    public subscript(host: String) -> String? { styles[host] }

    public func hiddenElements(for host: String) -> [HiddenSiteElement] { hidden[host] ?? [] }

    public func font(for host: String) -> SiteStyleFont { fonts[host] ?? .original }

    /// A user-selected sRGB accent for a site, stored as `#RRGGBB`.
    public func accent(for host: String) -> String? { accents[host] }

    public func hiddenSelectors(for host: String) -> [String] { hiddenElements(for: host).filter { $0.shape == nil }.map(\.selector) }

    public func hasStyle(for host: String) -> Bool {
        styles[host] != nil || hidden[host] != nil || font(for: host) != .original || accent(for: host) != nil
    }

    public func setFont(_ font: SiteStyleFont, for host: String) throws {
        guard fonts[host] != font else { return }
        var updated = fonts
        updated[host] = font == .original ? nil : font
        if let fontsFileURL {
            try FileManager.default.createDirectory(at: fontsFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(updated).write(to: fontsFileURL, options: .atomic)
        }
        fonts = updated
        revision += 1
    }

    public func setAccent(_ accent: String?, for host: String) throws {
        let value = accent.flatMap(Self.normalizedAccent)
        guard accents[host] != value else { return }
        var updated = accents
        updated[host] = value
        if let accentsFileURL {
            try FileManager.default.createDirectory(at: accentsFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(updated).write(to: accentsFileURL, options: .atomic)
        }
        accents = updated
        revision += 1
    }

    public func exportData(for host: String) -> Data? {
        let file = SharedSiteStyle(host: host, css: styles[host], font: font(for: host),
                                   accent: accent(for: host), hiddenElements: hiddenElements(for: host))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(file)
    }

    /// Imports a portable Ark Boost after validating its host and version.
    /// Existing presentation choices for that host are deliberately replaced as one user action.
    @discardableResult
    public func importData(_ data: Data) throws -> String? {
        let file = try JSONDecoder().decode(SharedSiteStyle.self, from: data)
        guard file.arkBoost == 1,
              let host = Self.host(of: URL(string: "https://" + file.host)), host == file.host,
              file.hiddenElements.allSatisfy({ element in
                  guard let shape = element.shape else { return true }
                  return shape.valid && !element.selector.isEmpty && element.fingerprint?.isEmpty == false
              }) else {
            return nil
        }
        try set(file.css ?? "", for: host)
        try setFont(file.font, for: host)
        try setAccent(file.accent, for: host)
        try setHidden(file.hiddenElements, for: host)
        return host
    }

    /// Avoid putting arbitrary persisted text into a page stylesheet.
    nonisolated public static func normalizedAccent(_ value: String) -> String? {
        let hex = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard candidate.count == 3 || candidate.count == 6,
              candidate.allSatisfy({ $0.isHexDigit }) else { return nil }
        if candidate.count == 3 {
            return "#" + candidate.map { "\($0)\($0)" }.joined().uppercased()
        }
        return "#" + candidate.uppercased()
    }

    public func hide(_ selector: String, for host: String) throws {
        try hide(HiddenSiteElement(selector: selector, label: selector), for: host)
    }

    public func hide(_ element: HiddenSiteElement, for host: String) throws {
        let elements = hiddenElements(for: host)
        guard !element.selector.isEmpty, !elements.contains(where: { $0.selector == element.selector }) else { return }
        try setHidden(elements + [element], for: host)
    }

    /// Save a bounded geometry change only for a fingerprinted element, avoiding unguarded moves.
    public func shape(_ element: HiddenSiteElement, for host: String) throws {
        guard !element.selector.isEmpty, element.fingerprint?.isEmpty == false,
              element.shape?.valid == true else { throw CocoaError(.validationMissingMandatoryProperty) }
        var elements = hiddenElements(for: host)
        if let index = elements.firstIndex(where: { $0.selector == element.selector }) { elements[index] = element }
        else { elements.append(element) }
        try setHidden(elements, for: host)
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
        let accentCSS = accent(for: host).map {
            ":root { accent-color: \($0) !important; } a:link, a:visited { color: \($0) !important; } ::selection { background: \($0) !important; color: white !important; }"
        }
        let css = [font(for: host).css.map { ":where(body, p, li, h1, h2, h3, h4, h5, h6, a, td, th, dd, dt, blockquote, input, textarea, button, label, figcaption) { font-family: \($0) !important; }" }, accentCSS, styles[host]]
            .compactMap { $0 }.joined(separator: "\n")
        revision += 1
        let applyRevision = revision
        let hiddenElements = hiddenElements(for: host).filter { $0.selector != selectorToShow }
        let selectors = hiddenElements.compactMap { ($0.fingerprint?.isEmpty ?? true) && $0.shape == nil ? $0.selector : nil }
        let guarded = hiddenElements.compactMap { element -> [String: String]? in
            guard let fingerprint = element.fingerprint, !fingerprint.isEmpty else { return nil }
            var rule = "display: none !important"
            if let shape = element.shape, shape.valid {
                var parts: [String] = []
                if let width = shape.width { parts.append("width: \(width.rounded())px !important; max-width: none !important; min-width: 0 !important; flex: none !important; box-sizing: border-box !important") }
                if let height = shape.height { parts.append("height: \(height.rounded())px !important; max-height: none !important; min-height: 0 !important; box-sizing: border-box !important") }
                if shape.dx != nil || shape.dy != nil { parts.append("translate: \((shape.dx ?? 0).rounded())px \((shape.dy ?? 0).rounded())px !important") }
                rule = parts.joined(separator: "; ")
            } else if element.shape != nil { return nil }
            return ["key": element.guardKey, "selector": element.selector, "fingerprint": fingerprint,
                    "family": element.family ?? "", "rule": rule]
        }
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
            const guardState = globalThis.arkHiddenElementGuard;
            if (!css && hidden.length === 0 && guarded.length === 0 && !showing) {
                if (sheet) document.adoptedStyleSheets = document.adoptedStyleSheets.filter(item => !isArkSheet(item));
                guardState?.update([]);
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
                for (const item of guarded) {
                    try { sheet.insertRule(`[data-ark-hidden~="${item.key}"] { ${item.rule}; }`, sheet.cssRules.length); } catch {}
                }
                if (showing) {
                    try { sheet.insertRule(`:is(${showing}):not(#ark-preview):not(#ark-preview):not(#ark-preview) { outline: 2px solid rgba(23, 23, 23, .9) !important; outline-offset: 2px !important; }`, sheet.cssRules.length); } catch {}
                }
                sheet.insertRule(':root { --ark-site-style: 1; }', sheet.cssRules.length);
            }
            if (!installed) document.adoptedStyleSheets = [...document.adoptedStyleSheets, sheet];
            if (!globalThis.arkHiddenElementGuard) {
                const fingerprint = element => {
                    const media = /^(IMG|VIDEO|IFRAME)$/.test(element.tagName) ? element : element.querySelector('img,video,iframe');
                    const source = media ? (media.getAttribute('src') || '').split('?')[0].slice(0, 200) : '';
                    const text = (element.textContent || '').replace(/\\s+/g, ' ').trim().slice(0, 160);
                    return element.tagName.toLowerCase() + '\\n' + source + '\\n' + text;
                };
                const setMarker = (element, key, enabled) => {
                    const values = (element.getAttribute('data-ark-hidden') || '').split(' ')
                        .filter(value => value && value !== key);
                    if (enabled) values.push(key);
                    if (values.length) element.setAttribute('data-ark-hidden', values.join(' '));
                    else element.removeAttribute('data-ark-hidden');
                };
                let items = [], observer;
                const applyGuards = () => {
                    for (const item of items) {
                        let matches = [];
                        try { matches = [...document.querySelectorAll(item.selector)].filter(element => fingerprint(element) === item.fingerprint); } catch {}
                        if (!matches.length && item.family) {
                            try { matches = [...document.querySelectorAll(item.family)].filter(element => fingerprint(element) === item.fingerprint); } catch {}
                        }
                        if (matches.length !== 1) matches = [];
                        document.querySelectorAll(`[data-ark-hidden~="${item.key}"]`).forEach(element => {
                            if (!matches.includes(element)) setMarker(element, item.key, false);
                        });
                        matches.forEach(element => setMarker(element, item.key, true));
                    }
                };
                globalThis.arkHiddenElementGuard = {
                    update(next) {
                        const activeKeys = new Set(next.map(item => item.key));
                        for (const item of items) {
                            if (!activeKeys.has(item.key)) {
                                document.querySelectorAll(`[data-ark-hidden~="${item.key}"]`).forEach(element => setMarker(element, item.key, false));
                            }
                        }
                        items = next;
                        if (!next.length) {
                            observer?.disconnect();
                            observer = undefined;
                            document.querySelectorAll('[data-ark-hidden]').forEach(element => element.removeAttribute('data-ark-hidden'));
                            return;
                        }
                        if (!observer && next.length) {
                            observer = new MutationObserver(applyGuards);
                            observer.observe(document, { childList: true, subtree: true, characterData: true,
                                attributes: true, attributeFilter: ['src', 'class', 'id'] });
                        }
                        applyGuards();
                    }
                };
            }
            globalThis.arkHiddenElementGuard.update(guarded);
            globalThis.arkSiteStyle = { revision };
            if (showing) {
                try { document.querySelector(showing)?.scrollIntoView({ block: 'center', behavior: 'smooth' }); } catch {}
            }
            """, arguments: ["host": host, "css": css, "hidden": selectors, "guarded": guarded,
                             "showing": selectorToShow as Any? ?? NSNull(),
                             "revision": applyRevision], in: nil,
            contentWorld: .world(name: "ark.site-style"))
    }
}
