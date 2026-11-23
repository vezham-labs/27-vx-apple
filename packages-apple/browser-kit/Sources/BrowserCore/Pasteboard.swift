#if os(iOS)
import UIKit
import UniformTypeIdentifiers
import WebKit

extension BrowserState {
    public enum PageSelectionMode { case area, element }

    private enum Capture {
        case page
        case area(CGRect)
        case element(CGPoint)

        var confirmation: String {
            switch self {
            case .page: "Full page image copied"
            case .area: "Page area copied"
            case .element: "Page element copied"
            }
        }
    }

    /// Copies a link, minus any tracking parameters when link cleaning is on.
    public func copyToPasteboard(_ url: URL) {
        UIPasteboard.general.url = settings.cleanLinks ? LinkCleaner.cleaned(url) : url
    }

    public func copyFullPageImage(of tab: BrowserTab) {
        guard !isCapturingPage, currentTab === tab, let url = tab.url else { return }
        captureImage(.page, of: tab, url: url)
    }

    public func selectPageCapture(_ mode: PageSelectionMode, of tab: BrowserTab) {
        guard !isCapturingPage, currentTab === tab, let url = tab.url else { return }
        pageCaptureTarget = (tab.id, url, mode)
    }

    public func pageCaptureMode(of tab: BrowserTab) -> PageSelectionMode? {
        guard currentTab === tab, let target = pageCaptureTarget,
              target.id == tab.id, target.url == tab.url else { return nil }
        return target.mode
    }

    public func cancelPageCapture(of tab: BrowserTab) {
        if pageCaptureTarget?.id == tab.id { pageCaptureTarget = nil }
    }

    public func copyPageArea(_ selection: CGRect, of tab: BrowserTab) {
        guard !isCapturingPage, pageCaptureMode(of: tab) == .area, let url = tab.url else { return }
        cancelPageCapture(of: tab)
        captureImage(.area(selection), of: tab, url: url)
    }

    public func copyPageElement(at point: CGPoint, of tab: BrowserTab) {
        guard !isCapturingPage, pageCaptureMode(of: tab) == .element, let url = tab.url else { return }
        cancelPageCapture(of: tab)
        captureImage(.element(point), of: tab, url: url)
    }

    private func captureImage(_ capture: Capture, of tab: BrowserTab, url: URL) {
        let webView = session(for: tab).webView
        guard let window = webView.window else {
            showToast("Couldn’t capture this page")
            return
        }
        let backingScale = window.traitCollection.displayScale
        isCapturingPage = true
        Task {
            defer { isCapturingPage = false }
            let png: Data?
            if case .page = capture {
                let pdf = try? await webView.pdf(configuration: WKPDFConfiguration())
                guard currentTab === tab, tab.url == url else { return }
                png = if let pdf { await PageCaptureImage.png(from: pdf, backingScale: backingScale) } else { nil }
            } else {
                let rect: CGRect?
                switch capture {
                case .page: rect = nil
                case .area(let selection): rect = selection.integral.intersection(webView.bounds)
                case .element(let point): rect = await PageCaptureImage.element(at: point, in: webView)
                }
                guard currentTab === tab, tab.url == url else { return }
                guard let rect, rect.width >= 2, rect.height >= 2 else {
                    showToast("Couldn’t capture this selection")
                    return
                }
                let configuration = WKSnapshotConfiguration()
                configuration.rect = rect
                if let width = PageCaptureImage.snapshotWidth(for: rect, backingScale: backingScale) {
                    configuration.snapshotWidth = NSNumber(value: width)
                }
                let image = try? await webView.takeSnapshot(configuration: configuration)
                guard currentTab === tab, tab.url == url else { return }
                png = if let cgImage = image?.cgImage { await PageCaptureImage.png(from: cgImage) } else { nil }
            }
            guard currentTab === tab, tab.url == url else { return }
            guard let png else {
                showToast("Couldn’t capture this image")
                return
            }
            UIPasteboard.general.setItems([[UTType.png.identifier: png]], options: [.localOnly: true])
            showToast(capture.confirmation)
        }
    }
}
#endif
