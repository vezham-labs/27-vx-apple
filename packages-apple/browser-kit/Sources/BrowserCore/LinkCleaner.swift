import Foundation

/// Strips click-tracking parameters (utm_*, fbclid, gclid…) from links before they load, and
/// from links you copy or share. Only parameters whose sole job is tracking are removed, so
/// pages still get everything they need.
public enum LinkCleaner {
    /// Removed on every site.
    static let global: Set<String> = [
        // Ad click IDs
        "fbclid", "gclid", "gclsrc", "dclid", "gbraid", "wbraid", "msclkid", "yclid", "ttclid",
        "twclid", "li_fat_id", "epik", "srsltid",
        // Email and marketing platforms
        "mc_cid", "mc_eid", "_hsenc", "_hsmi", "__hssc", "__hstc", "__hsfp", "hsctatracking",
        "mkt_tok", "oly_anon_id", "oly_enc_id", "vero_id", "vero_conv", "_kx", "ck_subscriber_id",
        "rb_clickid", "s_cid", "wickedid", "ml_subscriber", "ml_subscriber_hash",
        // Social share tags
        "igshid", "igsh",
    ]
    /// Removed when the name starts with one of these.
    static let prefixes = ["utm_", "pk_", "mtm_"]
    /// These commonly authenticate the whole request, including the query string.
    static let signatures: Set<String> = ["x-amz-signature", "x-goog-signature", "signature", "sig"]
    /// Removed only on these sites, where the name is generic elsewhere.
    static let perSite: [String: Set<String>] = [
        "youtube.com": ["si", "pp", "feature"],
        "youtu.be": ["si", "feature"],
        "open.spotify.com": ["si", "context"],
        "twitter.com": ["s", "t", "ref_src", "ref_url"],
        "x.com": ["s", "t", "ref_src", "ref_url"],
        "instagram.com": ["igsh", "img_index"],
        "tiktok.com": ["_r", "_t", "is_from_webapp", "sender_device", "sender_web_id"],
        "amazon.com": ["ref_", "pd_rd_r", "pd_rd_w", "pd_rd_wg", "pf_rd_r", "pf_rd_p", "pd_rd_i", "content-id"],
        "reddit.com": ["share_id", "rdt", "ref_campaign", "ref_source"],
        "linkedin.com": ["trk", "trkinfo", "lipi", "trackingid", "refid"],
    ]

    /// The URL without tracking parameters, or nil when there was nothing to remove.
    public static func clean(_ url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              var parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let query = parts.percentEncodedQuery, !query.isEmpty else { return nil }
        let siteParams = trackingParameters(for: (parts.host ?? "").lowercased())
        // Keep ranges of the encoded fields so values and separators survive unchanged.
        let fields = query.utf8.split(separator: UInt8(ascii: "&"), omittingEmptySubsequences: false)
        var kept: [Range<String.Index>] = []
        for field in fields {
            let rawName = String(decoding: field.prefix { $0 != UInt8(ascii: "=") }, as: UTF8.self)
            let decoded = rawName.utf8.contains(UInt8(ascii: "%")) ? rawName.removingPercentEncoding : nil
            let name = (decoded ?? rawName).lowercased()
            if signatures.contains(name) { return nil }
            if !global.contains(name), !siteParams.contains(name), !prefixes.contains(where: { name.hasPrefix($0) }) {
                kept.append(field.startIndex..<field.endIndex)
            }
        }
        guard kept.count != fields.count else { return nil }
        parts.percentEncodedQuery = kept.isEmpty ? nil : kept.map { query[$0] }.joined(separator: "&")
        return parts.url
    }

    private static func trackingParameters(for host: String) -> Set<String> {
        var domain = host[...]
        while !domain.isEmpty {
            if let parameters = perSite[String(domain)] { return parameters }
            guard let dot = domain.firstIndex(of: ".") else { break }
            domain = domain[domain.index(after: dot)...]
        }
        return []
    }

    /// `clean(url)` if anything was removed, otherwise the URL itself.
    public static func cleaned(_ url: URL) -> URL { clean(url) ?? url }
}
