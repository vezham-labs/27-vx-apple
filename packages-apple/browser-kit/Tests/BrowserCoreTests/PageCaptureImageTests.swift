import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import BrowserCore

struct PageCaptureImageTests {
    @Test func viewportKeepsNativeSizeOrFitsBothLimits() {
        #expect(PageCaptureImage.snapshotWidth(for: CGRect(x: 0, y: 0, width: 300, height: 180),
                                               backingScale: 3) == nil)
        #expect(PageCaptureImage.snapshotWidth(for: CGRect(x: 0, y: 0, width: 4_000, height: 4_000),
                                               backingScale: 2) == 2_000)
        #expect(PageCaptureImage.snapshotWidth(for: CGRect(x: 0, y: 0, width: 100, height: 20_000),
                                               backingScale: 2) == 40)
    }

    @Test func fullPDFHeightSurvivesRasterization() async throws {
        let pdf = try makePDF(width: 24, height: 120)
        let png = try #require(await PageCaptureImage.png(from: pdf, backingScale: 2))
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 48)
        #expect(image.height == 240)
    }

    @Test func captureRespectsMaximumDimension() async throws {
        let pdf = try makePDF(width: 20, height: 20_000)
        let png = try #require(await PageCaptureImage.png(from: pdf, backingScale: 3))
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 16)
        #expect(image.height == 16_384)
    }

    private func makePDF(width: Int, height: Int) throws -> Data {
        let data = NSMutableData()
        let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
        var box = CGRect(x: 0, y: 0, width: width, height: height)
        let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(red: 0, green: 0.3, blue: 1, alpha: 1))
        context.fill(box)
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }
}
