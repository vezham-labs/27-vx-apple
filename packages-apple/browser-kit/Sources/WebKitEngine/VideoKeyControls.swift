#if os(macOS)
import WebKit

/// Optional keyboard controls for a focused native media element. Runs in an
/// isolated world so page scripts cannot inspect or replace Ark's listener.
enum VideoKeyControls {
    static let worldName = "ark.video-keys"
    /// Retain the world while listeners exist, including after user scripts are replaced.
    @MainActor static let world = WKContentWorld.world(name: worldName)

    @MainActor
    static var script: WKUserScript {
        WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false,
                     in: world)
    }

    static let off = "window.__arkVideoKeysOff = true;"

    static let source = #"""
    (() => {
      window.__arkVideoKeysOff = false;
      if (window.__arkVideoKeys) return;
      window.__arkVideoKeys = true;
      document.addEventListener('keydown', (e) => {
        if (window.__arkVideoKeysOff || e.defaultPrevented || e.metaKey || e.ctrlKey || e.altKey) return;
        const media = e.target;
        if (!(media instanceof HTMLMediaElement) || !media.controls) return;
        if (document.fullscreenElement || media.webkitDisplayingFullscreen) return;
        if (e.key === ' ' && !e.shiftKey) {
          if (media.paused || media.ended) media.play().catch(() => {}); else media.pause();
        } else if ((e.key === 'ArrowLeft' || e.key === 'ArrowRight') && !e.shiftKey && Number.isFinite(media.duration)) {
          const to = media.currentTime + (e.key === 'ArrowRight' ? 5 : -5);
          media.currentTime = Math.max(0, Math.min(media.duration, to));
        } else return;
        e.preventDefault();
      });
    })();
    """#
}
#endif
