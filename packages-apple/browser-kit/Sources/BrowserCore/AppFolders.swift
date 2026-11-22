import Foundation

/// Where Ark keeps its files.
///
/// Sandboxed (iOS, and the Mac app until it left the App Sandbox) the system's Application Support
/// and Caches folders are the app's own container, so files go straight in. Outside the sandbox
/// those folders are shared by every app, so Ark's files go in a folder named for its bundle ID:
/// `~/Library/Application Support/app.vezham.ark/Browser/state.json`, say.
public enum AppFolders {
    public static var isSandboxed: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

    /// Application Support, Ark's own part of it.
    public static var support: URL { own(URL.applicationSupportDirectory) }

    /// Caches, Ark's own part of it.
    public static var caches: URL { own(URL.cachesDirectory) }

    private static func own(_ base: URL) -> URL {
        #if os(macOS)
        if !isSandboxed, let id = Bundle.main.bundleIdentifier {
            return base.appending(path: id, directoryHint: .isDirectory)
        }
        #endif
        return base
    }
}
