#if os(macOS)
import WebKit

enum PrivacySwitches {
    /// Use WebKit's native GPC request header and Navigator property when the platform provides it.
    @MainActor static func globalPrivacyControl(_ enabled: Bool, in preferences: WKWebpagePreferences) {
        let setter = NSSelectorFromString("setGlobalPrivacyControlEnabled:")
        guard preferences.responds(to: setter) else { return }
        typealias Setter = @convention(c) (AnyObject, Selector, Bool) -> Void
        unsafeBitCast(preferences.method(for: setter), to: Setter.self)(preferences, setter, enabled)
    }
}
#endif
