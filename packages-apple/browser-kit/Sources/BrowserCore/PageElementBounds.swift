import WebKit

extension PageCaptureImage {
    /// Converts a point and the hit element's rectangle between the native view and CSS viewport.
    @MainActor
    public static func element(at point: CGPoint, in webView: WKWebView) async -> CGRect? {
        guard webView.bounds.contains(point) else { return nil }
        #if os(iOS)
        let scrollOffset = webView.scrollView.contentOffset
        let origin = CGPoint(x: max(0, -scrollOffset.x), y: max(0, -scrollOffset.y))
        #else
        let origin = CGPoint.zero
        #endif
        let results = try? await webView.callAsyncJavaScript("""
            const viewport = window.visualViewport;
            const scale = pageZoom * (viewport?.scale ?? 1);
            const offsetX = viewport?.offsetLeft ?? 0;
            const offsetY = viewport?.offsetTop ?? 0;
            const element = document.elementFromPoint((x - originX) / scale + offsetX,
                                                      (y - originY) / scale + offsetY);
            if (!element || element === document.documentElement || element === document.body) return null;
            const rect = element.getBoundingClientRect();
            return [originX + (rect.left - offsetX) * scale, originY + (rect.top - offsetY) * scale,
                    rect.width * scale, rect.height * scale];
            """, arguments: ["x": point.x, "y": point.y, "originX": origin.x, "originY": origin.y,
                             "pageZoom": webView.pageZoom],
            in: nil, contentWorld: .world(name: "Ark Page Capture"))
        guard let values = results as? [NSNumber], values.count == 4 else { return nil }
        let coordinates = values.map(\.doubleValue)
        guard coordinates.allSatisfy(\.isFinite), coordinates[2] > 0, coordinates[3] > 0 else { return nil }
        let rect = CGRect(x: coordinates[0], y: coordinates[1], width: coordinates[2], height: coordinates[3])
            .integral.intersection(webView.bounds)
        return rect.width >= 2 && rect.height >= 2 ? rect : nil
    }

    /// Returns a unique, stable-enough CSS selector for the element under a native touch point.
    @MainActor
    public static func selector(at point: CGPoint, in webView: WKWebView) async -> String? {
        guard webView.bounds.contains(point) else { return nil }
        #if os(iOS)
        let scrollOffset = webView.scrollView.contentOffset
        let origin = CGPoint(x: max(0, -scrollOffset.x), y: max(0, -scrollOffset.y))
        #else
        let origin = CGPoint.zero
        #endif
        let result = try? await webView.callAsyncJavaScript("""
            const viewport = window.visualViewport;
            const scale = pageZoom * (viewport?.scale ?? 1);
            const offsetX = viewport?.offsetLeft ?? 0;
            const offsetY = viewport?.offsetTop ?? 0;
            const element = document.elementFromPoint((x - originX) / scale + offsetX,
                                                      (y - originY) / scale + offsetY);
            if (!element || element === document.documentElement || element === document.body) return null;
            const unique = selector => {
                try { return document.querySelectorAll(selector).length === 1; } catch { return false; }
            };
            if (element.id) {
                const selector = '#' + CSS.escape(element.id);
                if (unique(selector)) return selector;
            }
            for (const attribute of ['data-testid', 'data-test', 'data-qa', 'data-cy', 'aria-label', 'name', 'role']) {
                const value = element.getAttribute(attribute);
                if (!value) continue;
                const selector = element.tagName.toLowerCase() + '[' + attribute + '="' + CSS.escape(value) + '"]';
                if (unique(selector)) return selector;
            }
            const classes = (typeof element.className === 'string' ? element.className : '')
                .trim().split(/\\s+/).filter(name => /^[a-zA-Z][\\w-]{2,29}$/.test(name) && !/\\d{3,}/.test(name));
            if (classes.length) {
                const selector = element.tagName.toLowerCase() + '.' + classes.map(CSS.escape).join('.');
                if (unique(selector)) return selector;
            }
            const parts = [];
            let node = element;
            while (node && node.nodeType === 1 && node !== document.documentElement) {
                if (node.id) {
                    const selector = '#' + CSS.escape(node.id);
                    if (unique(selector)) { parts.unshift(selector); break; }
                }
                const name = node.tagName.toLowerCase();
                const parent = node.parentElement;
                if (!parent) { parts.unshift(name); break; }
                const siblings = Array.from(parent.children).filter(item => item.tagName === node.tagName);
                parts.unshift(siblings.length > 1 ? name + ':nth-of-type(' + (siblings.indexOf(node) + 1) + ')' : name);
                node = parent;
            }
            const selector = parts.join(' > ');
            return selector && unique(selector) ? selector : null;
            """, arguments: ["x": point.x, "y": point.y, "originX": origin.x, "originY": origin.y,
                             "pageZoom": webView.pageZoom], in: nil, contentWorld: .world(name: "Ark Page Capture"))
        guard let selector = result as? String, !selector.isEmpty else { return nil }
        return selector
    }
}
