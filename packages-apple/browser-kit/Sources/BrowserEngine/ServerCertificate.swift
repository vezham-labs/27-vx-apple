import Foundation

/// A certificate the browser can identify after the system rejects it.
public struct ServerCertificate: Sendable, Equatable {
    public let host: String
    public let port: Int
    public let fingerprint: String

    public init(host: String, port: Int, fingerprint: String) {
        self.host = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
        self.port = port
        self.fingerprint = fingerprint
    }

    public var site: String { Self.site(host: host, port: port) }

    public static func site(host: String, port: Int?) -> String {
        "\(host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()):\(port ?? 443)"
    }

    public static let errorUserInfoKey = "ArkCertificateFingerprint"
}
