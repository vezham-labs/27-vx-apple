import XCTest

@MainActor
final class PageCaptureUITests: XCTestCase {
    func testCopiesFullPageImage() throws {
        let app = launchPage()
        try selectPageCommand("Copy Full Page Image", in: app)
        XCTAssertTrue(app.staticTexts["Full page image copied"].waitForExistence(timeout: 15))
    }

    func testCopiesSelectedPageArea() throws {
        let app = launchPage()
        try selectPageCommand("Copy Page Area…", in: app)
        let surface = app.descendants(matching: .any)["page-capture-surface"].firstMatch
        XCTAssertTrue(surface.waitForExistence(timeout: 10))
        let copy = app.buttons["Copy Area"]
        XCTAssertTrue(copy.exists)
        XCTAssertFalse(copy.isEnabled)
        let start = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.33))
        let end = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.72, dy: 0.55))
        start.press(forDuration: 0.1, thenDragTo: end)
        XCTAssertTrue(copy.isEnabled)
        copy.tap()
        XCTAssertTrue(app.staticTexts["Page area copied"].waitForExistence(timeout: 15))
        XCTAssertTrue(surface.waitForNonExistence(timeout: 5))
    }

    func testCopiesPageElement() throws {
        let app = launchPage(captureFixture: true)
        let target = app.webViews.firstMatch.staticTexts["Capture target"]
        XCTAssertTrue(target.waitForExistence(timeout: 10))
        let frame = target.frame

        try selectPageCommand("Copy Page Element…", in: app)
        let surface = app.descendants(matching: .any)["page-capture-surface"].firstMatch
        XCTAssertTrue(surface.waitForExistence(timeout: 10))
        let viewport = surface.frame
        XCTAssertTrue(viewport.contains(CGPoint(x: frame.midX, y: frame.midY)))
        surface.coordinate(withNormalizedOffset: CGVector(dx: (frame.midX - viewport.minX) / viewport.width,
                                                        dy: (frame.midY - viewport.minY) / viewport.height)).tap()
        XCTAssertTrue(app.staticTexts["Page element copied"].waitForExistence(timeout: 15))
    }

    private func launchPage(captureFixture: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "1"]
        if captureFixture { app.launchArguments.append("--capture-fixture") }
        app.launch()
        XCTAssertTrue(app.webViews.firstMatch.staticTexts["Tab 1"].waitForExistence(timeout: 30))
        return app
    }

    private func selectPageCommand(_ title: String, in app: XCUIApplication) throws {
        let more = app.buttons["More"].firstMatch
        if !more.exists {
            // The address capsule exposes its favicon, text, and reload control separately.
            let address = try XCTUnwrap(app.buttons.matching(identifier: "Tab 1").allElementsBoundByIndex
                .first { $0.frame.width > 44 })
            address.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        XCTAssertTrue(more.waitForExistence(timeout: 10))
        more.tap()
        let capture = app.descendants(matching: .any)[title].firstMatch
        XCTAssertTrue(capture.waitForExistence(timeout: 10))
        capture.tap()
    }
}
