import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public enum PageCaptureImage {
    /// Rasterizes WebKit's full-page PDF away from the main actor.
    public static func png(from pdf: Data, backingScale: CGFloat) async -> Data? {
        await Task.detached(priority: .userInitiated) {
            renderPNG(from: pdf, backingScale: backingScale)
        }.value
    }

    public static func png(from image: CGImage) async -> Data? {
        await Task.detached(priority: .userInitiated) { encodePNG(image) }.value
    }

    /// WebKit's custom snapshot width is in points, before applying the screen scale.
    public static func snapshotWidth(for rect: CGRect, backingScale: CGFloat) -> CGFloat? {
        guard backingScale.isFinite, backingScale > 0, rect.width.isFinite, rect.height.isFinite,
              rect.width >= 2, rect.height >= 2 else { return nil }
        let scale = fittedScale(for: rect.size, backingScale: backingScale)
        guard scale < backingScale else { return nil }
        return max(1, (rect.width * scale / backingScale).rounded(.down))
    }

    // Adapted from Search's SnapGeometry. WebKit's PDF includes offscreen content.
    private static func renderPNG(from pdf: Data, backingScale: CGFloat) -> Data? {
        guard backingScale.isFinite, backingScale > 0 else { return nil }
        guard let provider = CGDataProvider(data: pdf as CFData),
              let document = CGPDFDocument(provider), let page = document.page(at: 1) else { return nil }
        let bounds = page.getBoxRect(.mediaBox)
        guard bounds.width.isFinite, bounds.height.isFinite, bounds.width >= 1, bounds.height >= 1 else { return nil }

        // Scale down oversized pages while keeping the entire document in the image.
        let scale = fittedScale(for: bounds.size, backingScale: backingScale)
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
        return context.makeImage().flatMap(encodePNG)
    }

    private static func fittedScale(for size: CGSize, backingScale: CGFloat) -> CGFloat {
        min(backingScale, (16_000_000 / size.width / size.height).squareRoot(),
            16_384 / max(size.width, size.height))
    }

    private static func encodePNG(_ image: CGImage) -> Data? {
        let png = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? png as Data : nil
    }
}
