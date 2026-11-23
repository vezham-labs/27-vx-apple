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
}
