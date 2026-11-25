import WebKit

/// Relays the call-audio page script to a named content world so ordinary sites cannot detect
/// WebKit's `window.webkit.messageHandlers` bridge.
enum PageBridge {
    @MainActor static let world = WKContentWorld.world(name: "ArkPageBridge")

    /// Runs in Ark's isolated world before the site scripts. Only the call-audio handler is exposed.
    @MainActor static let relay = WKUserScript(source: #"""
    (() => {
      if (window.__arkBridgeRelay) return;
      window.__arkBridgeRelay = true;
      window.addEventListener('message', (event) => {
        const data = event.data;
        if (event.source !== window || !data || typeof data !== 'object' ||
            data.__arkBridge !== 'arkCallAudio' || typeof data.id !== 'string') return;
        const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.arkCallAudio;
        const reply = (ok, value) => window.postMessage({ __arkBridgeReply: data.id, ok, value }, '*');
        if (!handler) return reply(false, 'unavailable');
        Promise.resolve().then(() => handler.postMessage(data.body)).then(
          value => reply(true, value), error => reply(false, String(error && error.message || error)));
      });
    })();
    """#, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: world)

    /// Prefixes a page-world user script with a scoped helper for the isolated handler.
    static let pageHelper = #"""
    const __arkBridge = (() => {
      const waiting = new Map();
      let next = 0;
      window.addEventListener('message', event => {
        const data = event.data;
        if (event.source !== window || !data || typeof data !== 'object' || typeof data.__arkBridgeReply !== 'string') return;
        const pending = waiting.get(data.__arkBridgeReply);
        if (!pending) return;
        waiting.delete(data.__arkBridgeReply);
        data.ok ? pending.resolve(data.value) : pending.reject(new Error(data.value));
      });
      return name => ({ postMessage(body) {
        const id = 'ark' + Date.now().toString(36) + (next++) + Math.random().toString(36).slice(2, 8);
        return new Promise((resolve, reject) => {
          waiting.set(id, { resolve, reject });
          window.postMessage({ __arkBridge: name, id, body }, '*');
        });
      }});
    })();
    """#
}
