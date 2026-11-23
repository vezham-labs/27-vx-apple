import XCTest

@MainActor
final class SiteStyleUITests: XCTestCase {
    func testSavesAndClearsCSSOnThePage() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "1", "--site-style-fixture"]
        app.launch()
        let target = app.webViews.firstMatch.staticTexts["Style target"]
        XCTAssertTrue(target.waitForExistence(timeout: 30))

        try openEditor(in: app)
        let css = "#fixture-target { display: none }"
        let editor = app.textViews["Custom CSS"].firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap()
        editor.typeText(css)
        app.buttons["Save"].tap()
        XCTAssertTrue(target.waitForNonExistence(timeout: 15))

        try openEditor(in: app)
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        XCTAssertEqual(editor.value as? String, css)
        app.buttons["Clear CSS"].tap()
        app.buttons["Save"].tap()
        XCTAssertTrue(target.waitForExistence(timeout: 15))
    }

    private func openEditor(in app: XCUIApplication) throws {
        let more = app.buttons["More"].firstMatch
        if !more.exists {
            let address = try XCTUnwrap(app.buttons.matching(identifier: "Style Fixture").allElementsBoundByIndex
                .filter { $0.identifier != "arrow.clockwise" && $0.identifier != "xmark" }
                .max { $0.frame.width < $1.frame.width })
            address.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        XCTAssertTrue(more.waitForExistence(timeout: 10))
        more.tap()
        let command = app.descendants(matching: .any)["Edit Site Style…"].firstMatch
        XCTAssertTrue(command.waitForExistence(timeout: 10))
        command.tap()
    }
}
