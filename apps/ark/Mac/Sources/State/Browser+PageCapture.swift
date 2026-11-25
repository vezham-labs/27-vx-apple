import AppKit
import BrowserCore
import WebKit

extension Browser {
    /// Captures the current non-private page into a local Easel card without going through the clipboard.
    func captureCurrentPage(toEasel boardID: UUID) {
        guard !isCapturingPage, let tab = currentTab, !tab.isPrivate, let url = tab.url else { return }
        guard let webView = currentController?.page.view as? WKWebView, webView.window != nil else {
            showToast("Couldn’t capture this page")
            return
        }

        isCapturingPage = true
        Task {
            defer { isCapturingPage = false }
            let pdf = try? await webView.pdf(configuration: WKPDFConfiguration())
            guard currentTab === tab, tab.url == url else { return }
            guard let pdf else {
                showToast("Couldn’t capture this page")
                return
            }
            let png = await PageCaptureImage.png(from: pdf, backingScale: webView.window?.backingScaleFactor ?? 1)
            guard currentTab === tab, tab.url == url else { return }
            guard let png, library.easels.addImage(png, title: tab.title.isEmpty ? (url.host() ?? "Capture") : tab.title, to: boardID) else {
                showToast("Couldn’t add this capture to Easel")
                return
            }
            showToast("Page added to Easel")
        }
    }

    func copyFullPageImage(to clipboard: NSPasteboard = .general) {
        guard !isCapturingPage, let tab = currentTab, let url = tab.url else { return }
        guard let webView = currentController?.page.view as? WKWebView, webView.window != nil else {
            showToast("Couldn’t capture this page")
            return
        }

        isCapturingPage = true
        Task {
            defer { isCapturingPage = false }
            let pdf = try? await webView.pdf(configuration: WKPDFConfiguration())
            guard currentTab === tab, tab.url == url else { return }
            guard let pdf else {
                showToast("Couldn’t capture this page")
                return
            }
            let backingScale = webView.window?.backingScaleFactor ?? 1
            let png = await PageCaptureImage.png(from: pdf, backingScale: backingScale)
            guard currentTab === tab, tab.url == url else { return }
            guard let png else {
                showToast("Couldn’t capture this page")
                return
            }

            copyCapture(png, isPrivate: tab.isPrivate, to: clipboard, confirmation: "Full page image copied")
        }
    }

    @discardableResult
    func selectPageArea(to clipboard: NSPasteboard = .general) -> RegionCaptureView? {
        selectPageCapture(.area, to: clipboard)
    }

    @discardableResult
    func selectPageElement(to clipboard: NSPasteboard = .general) -> RegionCaptureView? {
        selectPageCapture(.element, to: clipboard)
    }

    private func selectPageCapture(_ mode: RegionCaptureView.Mode, to clipboard: NSPasteboard) -> RegionCaptureView? {
        guard !isCapturingPage, let tab = currentTab, let url = tab.url else { return nil }
        guard let webView = currentController?.page.view as? WKWebView,
              webView.window != nil, webView.superview != nil else {
            showToast("Couldn’t capture this page")
            return nil
        }
        let picker = RegionCaptureView.present(on: webView, mode: mode) { [weak self, weak webView] selection in
            guard let self, let webView, !isCapturingPage, currentTab === tab, tab.url == url else { return }
            isCapturingPage = true
            Task {
                defer { isCapturingPage = false }
                let rect: CGRect?
                switch selection {
                case .area(let area): rect = area
                case .element(let point): rect = await PageCaptureImage.element(at: point, in: webView)
                }
                guard currentTab === tab, tab.url == url else { return }
                let failure = mode == .area ? "Couldn’t capture this area" : "Couldn’t capture this element"
                guard let rect else {
                    showToast(failure)
                    return
                }
                let configuration = WKSnapshotConfiguration()
                configuration.rect = rect
                let backing = webView.window?.backingScaleFactor ?? 1
                if let width = PageCaptureImage.snapshotWidth(for: rect, backingScale: backing) {
                    configuration.snapshotWidth = NSNumber(value: width)
                }
                let snapshot = try? await webView.takeSnapshot(configuration: configuration)
                let image = snapshot?.cgImage(forProposedRect: nil, context: nil, hints: nil)
                let png: Data?
                if let image {
                    png = await PageCaptureImage.png(from: image)
                } else {
                    png = nil
                }
                guard currentTab === tab, tab.url == url else { return }
                guard let png else {
                    showToast(failure)
                    return
                }
                let confirmation = mode == .area ? "Page area copied" : "Page element copied"
                copyCapture(png, isPrivate: tab.isPrivate, to: clipboard, confirmation: confirmation)
            }
        }
        if picker != nil {
            showToast(mode == .area ? "Drag to select an area · Esc to cancel" : "Click an element · Esc to cancel")
        }
        return picker
    }

    private func copyCapture(_ png: Data, isPrivate: Bool, to clipboard: NSPasteboard, confirmation: String) {
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        if isPrivate {
            item.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        }
        clipboard.prepareForNewContents(with: .currentHostOnly)
        showToast(clipboard.writeObjects([item]) ? confirmation : "Couldn’t copy the page image")
    }
}
