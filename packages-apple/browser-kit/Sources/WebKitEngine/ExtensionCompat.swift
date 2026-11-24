#if os(macOS)
import Foundation
import CryptoKit

/// Prepares an unpacked extension built for Chrome to run in WebKit: copies it into Ark's own
/// folder, puts `extension-compat.js` in front of its background, and injects the same prelude into
/// extension HTML pages. The source extension remains unchanged.
enum ExtensionCompat {
    static let compatFile = "_ark_compat.js"
    static let entryFile = "_ark_background.js"
    static let diagnosticsFile = "_ark_diagnostics.js"
    static let keepAlivePage = "_ark_keepalive.html"

    /// The prepared copy of `source`, under `root`. Re-made each time, so it follows the source.
    static func prepare(_ source: URL, id: String, in root: URL) throws -> URL {
        let fm = FileManager.default
        let target = root.appending(path: folderName(for: id), directoryHint: .isDirectory)
        try? fm.removeItem(at: target)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try fm.copyItem(at: source, to: target)

        let manifestURL = target.appending(path: "manifest.json")
        guard var manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any] else {
            return target
        }
        guard let compat = Bundle.module.url(forResource: "extension-compat", withExtension: "js") else { return target }
        try fm.copyItem(at: compat, to: target.appending(path: compatFile))
        var preludes = [compatFile]
        #if DEBUG
        if ProcessInfo.processInfo.environment["ARK_EXT_DIAGNOSTICS"] != nil,
           let diagnostics = Bundle.module.url(forResource: "extension-diagnostics", withExtension: "js") {
            try fm.copyItem(at: diagnostics, to: target.appending(path: diagnosticsFile))
            preludes.append(diagnosticsFile)
        }
        #endif

        // The extension's own pages (popup, options, onboarding) get the compat script too: they use the
        // same missing APIs and user-agent checks as the background. Keep the doctype before any
        // injected script on pages without a <head>, or WebKit will render them in quirks mode.
        let signature = Data([0xEF, 0xBB, 0xBF])
        if let files = fm.enumerator(at: target, includingPropertiesForKeys: nil) {
            for case let file as URL in files where ["html", "htm"].contains(file.pathExtension.lowercased()) {
                guard let bytes = try? Data(contentsOf: file),
                      var html = String(data: bytes, encoding: .utf8) else { continue }
                if bytes.starts(with: signature), !html.hasPrefix("\u{FEFF}") {
                    html.insert("\u{FEFF}", at: html.startIndex)
                }
                let missingPreludes = preludes.filter { !html.contains("<script src=\"/\($0)\"></script>") }
                guard !missingPreludes.isEmpty else {
                    let preserved = Data(html.utf8)
                    if preserved != bytes { try? preserved.write(to: file, options: .atomic) }
                    continue
                }
                let tag = missingPreludes.map { "<script src=\"/\($0)\"></script>" }.joined()
                html = Self.inserting(tag, into: html)
                let rewritten = Data(html.utf8)
                if rewritten != bytes { try? rewritten.write(to: file, options: .atomic) }
            }
        }
        // A hidden extension page Ark keeps open (see WebKitExtensions.startKeepAlive). Its script is a
        // separate file because extension pages may not run inline scripts.
        if manifest["background"] != nil {
            try """
            <!doctype html><meta charset="utf-8"><title>Ark keep-alive</title><script src="_ark_keepalive.js"></script>
            """.write(to: target.appending(path: keepAlivePage), atomically: true, encoding: .utf8)
            try """
            // Called by Ark every 20 s: an incoming event keeps the background from being unloaded as idle.
            function ping() { try { chrome.runtime.sendMessage({ name: 'ark-keepalive' }).catch(() => {}); } catch (e) {} return Date.now(); }
            """.write(to: target.appending(path: "_ark_keepalive.js"), atomically: true, encoding: .utf8)
        }
        if var background = manifest["background"] as? [String: Any] {
            if let worker = background["service_worker"] as? String, isSafePath(worker) {
                // A module worker imports the compat script first; a classic one loads it with importScripts.
                let module = (background["type"] as? String) == "module"
                let entry = module
                    ? (preludes + [worker]).map { "import './\($0)';\n" }.joined()
                    : "importScripts(\((preludes + [worker]).map { "'/\($0)'" }.joined(separator: ", ")));\n"
                try entry.write(to: target.appending(path: entryFile), atomically: true, encoding: .utf8)
                background["service_worker"] = entryFile
            } else if let scripts = background["scripts"] as? [String] {
                background["scripts"] = preludes + scripts
            }
            manifest["background"] = background
        }
        // The compat script's WebSocket stand-in talks to Ark over native messaging.
        var permissions = (manifest["permissions"] as? [String]) ?? []
        if manifest["background"] != nil, !permissions.contains("nativeMessaging") {
            permissions.append("nativeMessaging")
            manifest["permissions"] = permissions
        }
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .withoutEscapingSlashes])
        try data.write(to: manifestURL)
        return target
    }

    /// Places the prelude in the head when one is present. Otherwise keep the HTML prolog intact
    /// and insert after the doctype and <html> tag, where the parser creates its implied head.
    private static func inserting(_ tag: String, into source: String) -> String {
        var html = source
        let options: String.CompareOptions = [.regularExpression, .caseInsensitive]
        if let head = html.range(of: #"<head(\s[^>]*)?>"#, options: options) {
            html.insert(contentsOf: tag, at: head.upperBound)
            return html
        }

        var insertion = html.startIndex
        if html.hasPrefix("\u{FEFF}") { insertion = html.index(after: insertion) }
        let prolog = [#"\s+"#, #"<!--[\s\S]*?-->"#, #"<!doctype[^>]*>"#]
        var passedHTML = false
        let anchored = options.union(.anchored)
        while insertion < html.endIndex {
            let remainder = html[insertion...]
            if let found = prolog.lazy.compactMap({ remainder.range(of: $0, options: anchored) }).first {
                insertion = found.upperBound
            } else if !passedHTML,
                      let found = remainder.range(of: #"<html(\s[^>]*)?>"#, options: anchored) {
                insertion = found.upperBound
                passedHTML = true
            } else {
                break
            }
        }
        html.insert(contentsOf: tag, at: insertion)
        return html
    }

    /// A folder name for an extension id. Ids can hold anything (a folder extension's is its path), so
    /// readable characters are kept and a hash keeps names apart.
    static func folderName(for id: String) -> String {
        let readable = String(id.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "-" }.suffix(40))
        let hash = SHA256.hash(data: Data(id.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
        return "\(readable)-\(hash)"
    }

    /// Paths written into the generated entry: plain relative file paths only.
    private static func isSafePath(_ path: String) -> Bool {
        !path.isEmpty && !path.contains("..") && path.allSatisfy { $0.isLetter || $0.isNumber || "._/-".contains($0) }
    }
}
#endif
