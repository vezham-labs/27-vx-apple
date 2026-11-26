import AppKit
import BrowserCore
import BrowserEngine
import UniformTypeIdentifiers
import WebKit

extension Browser {
    /// Captures the current non-private page into a local Easel card without going through the clipboard.
    func captureCurrentPage(toEasel boardID: UUID) {
        guard !isCapturingPage, let tab = currentTab, !tab.isPrivate, let url = tab.url else { return }
        guard let webView = currentController?.page.view as? WKWebView, webView.window != nil else {
            showToast("Couldn’t capture this page")
            return
        }
        let profile = library.browsingProfile(for: tab)

        isCapturingPage = true
        Task {
            defer { isCapturingPage = false }
            let pdf = try? await webView.pdf(configuration: WKPDFConfiguration())
            guard currentTab === tab, tab.url == url, library.browsingProfile(for: tab) == profile, library.existingController(for: tab)?.page?.view === webView else { return }
            guard let pdf else {
                showToast("Couldn’t capture this page")
                return
            }
            let png = await PageCaptureImage.png(from: pdf, backingScale: webView.window?.backingScaleFactor ?? 1)
            guard currentTab === tab, tab.url == url, library.browsingProfile(for: tab) == profile, library.existingController(for: tab)?.page?.view === webView else { return }
            guard let png, library.easels.addImage(png, title: tab.title.isEmpty ? (url.host() ?? "Capture") : tab.title, to: boardID) else {
                showToast("Couldn’t add this capture to Easel")
                return
            }
            showToast("Page added to Easel")
        }
    }

    func copyFullPageImage(to clipboard: NSPasteboard = .general, save: Bool = false) {
        guard !isCapturingPage, let tab = currentTab, let url = tab.url else { return }
        guard let webView = currentController?.page.view as? WKWebView, webView.window != nil else {
            showToast("Couldn’t capture this page")
            return
        }
        let profile = library.browsingProfile(for: tab)

        isCapturingPage = true
        Task {
            defer { isCapturingPage = false }
            let pdf = try? await webView.pdf(configuration: WKPDFConfiguration())
            guard currentTab === tab, tab.url == url, library.browsingProfile(for: tab) == profile, library.existingController(for: tab)?.page?.view === webView else { return }
            guard let pdf else {
                showToast("Couldn’t capture this page")
                return
            }
            let backingScale = webView.window?.backingScaleFactor ?? 1
            let png = await PageCaptureImage.png(from: pdf, backingScale: backingScale)
            guard currentTab === tab, tab.url == url, library.browsingProfile(for: tab) == profile, library.existingController(for: tab)?.page?.view === webView else { return }
            guard let png else {
                showToast("Couldn’t capture this page")
                return
            }

            finishCapture(png, save: save, window: webView.window, isPrivate: tab.isPrivate, to: clipboard, confirmation: "Full page image copied")
        }
    }

    @discardableResult
    func selectPageArea(to clipboard: NSPasteboard = .general, save: Bool = false) -> RegionCaptureView? {
        selectPageCapture(.area, to: clipboard, save: save)
    }

    @discardableResult
    func selectPageElement(to clipboard: NSPasteboard = .general, save: Bool = false) -> RegionCaptureView? {
        selectPageCapture(.element, to: clipboard, save: save)
    }

    private func selectPageCapture(_ mode: RegionCaptureView.Mode, to clipboard: NSPasteboard, save: Bool) -> RegionCaptureView? {
        guard !isCapturingPage, let tab = currentTab, let url = tab.url else { return nil }
        guard let webView = currentController?.page.view as? WKWebView,
              webView.window != nil, webView.superview != nil else {
            showToast("Couldn’t capture this page")
            return nil
        }
        let profile = library.browsingProfile(for: tab)
        let picker = RegionCaptureView.present(on: webView, mode: mode) { [weak self, weak webView] selection in
            guard let self, let webView, !isCapturingPage, currentTab === tab, tab.url == url,
                  library.browsingProfile(for: tab) == profile, library.existingController(for: tab)?.page?.view === webView else { return }
            isCapturingPage = true
            Task {
                defer { isCapturingPage = false }
                let rect: CGRect?
                switch selection {
                case .area(let area): rect = area
                case .element(let point, _): rect = await PageCaptureImage.element(at: point, in: webView)
                }
                guard currentTab === tab, tab.url == url, library.browsingProfile(for: tab) == profile, library.existingController(for: tab)?.page?.view === webView else { return }
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
                guard currentTab === tab, tab.url == url, library.browsingProfile(for: tab) == profile, library.existingController(for: tab)?.page?.view === webView else { return }
                guard let png else {
                    showToast(failure)
                    return
                }
                let confirmation = mode == .area ? "Page area copied" : "Page element copied"
                finishCapture(png, save: save, window: webView.window, isPrivate: tab.isPrivate, to: clipboard, confirmation: confirmation)
            }
        }
        if picker != nil {
            showToast(mode == .area ? "Drag to select an area · Esc to cancel" : "Click an element · Esc to cancel")
        }
        return picker
    }

    private func finishCapture(_ png: Data, save: Bool, window: NSWindow?, isPrivate: Bool, to clipboard: NSPasteboard, confirmation: String) {
        guard save else {
            copyCapture(png, isPrivate: isPrivate, to: clipboard, confirmation: confirmation)
            return
        }
        guard let window else { showToast("Couldn’t save the page image"); return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "Page Capture.png"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do {
                try self.writePageCapture(png, to: url, isPrivate: isPrivate)
                self.showToast("Page image saved")
            } catch {
                self.showToast("Couldn’t save the page image")
            }
        }
    }

    func writePageCapture(_ png: Data, to url: URL, isPrivate: Bool) throws {
        try png.write(to: url, options: .atomic)
        guard !isPrivate else { return }
        let item = EngineDownload(filename: url.lastPathComponent, sourceURL: nil)
        item.fileURL = url
        item.progress = 1
        item.status = .finished
        library.downloads.append(item)
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
