import AppKit
import WebKit

extension Browser {
    func copyFullPageImage() {
        guard let tab = currentTab, let url = tab.url else { return }
        guard let webView = currentController?.page.view as? WKWebView, webView.window != nil else {
            showToast("Couldn’t capture this page")
            return
        }

        Task {
            let pdf = try? await webView.pdf(configuration: WKPDFConfiguration())
            guard currentTab === tab, tab.url == url else { return }
            guard let pdf, let image = fullPageImage(from: pdf, backingScale: webView.window?.backingScaleFactor ?? 1),
                  let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                showToast("Couldn’t capture this page")
                return
            }

            let item = NSPasteboardItem()
            item.setData(png, forType: .png)
            if tab.isPrivate {
                item.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
            }
            let clipboard = NSPasteboard.general
            clipboard.prepareForNewContents(with: .currentHostOnly)
            showToast(clipboard.writeObjects([item]) ? "Full page image copied" : "Couldn’t copy the page image")
        }
    }
}

// Adapted from Search's SnapGeometry. WebKit's PDF includes offscreen content.
private func fullPageImage(from pdf: Data, backingScale: CGFloat) -> CGImage? {
    guard let provider = CGDataProvider(data: pdf as CFData),
          let document = CGPDFDocument(provider), let page = document.page(at: 1) else { return nil }
    let bounds = page.getBoxRect(.mediaBox)
    guard bounds.width.isFinite, bounds.height.isFinite, bounds.width >= 1, bounds.height >= 1 else { return nil }

    // Scale down oversized pages while keeping the entire document in the image.
    let pixelBudget: CGFloat = 16_000_000
    let maxDimension: CGFloat = 16_384
    let scale = min(backingScale, (pixelBudget / bounds.width / bounds.height).squareRoot(),
                    maxDimension / max(bounds.width, bounds.height))
    let width = max(1, Int((bounds.width * scale).rounded(.down)))
    let height = max(1, Int((bounds.height * scale).rounded(.down)))
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }

    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.scaleBy(x: CGFloat(width) / bounds.width, y: CGFloat(height) / bounds.height)
    context.translateBy(x: -bounds.minX, y: -bounds.minY)
    context.drawPDFPage(page)
    return context.makeImage()
}
