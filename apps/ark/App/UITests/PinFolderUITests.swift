import XCTest

@MainActor
final class PinFolderUITests: XCTestCase {
    func testCreatesAndCollapsesFolderInTheTabGallery() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "1", "--posture", "folded"]
        app.launch()
        let tabs = app.buttons["Tabs"].firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 30))
        tabs.tap()
        let newFolder = app.buttons["New Pin Folder"]
        XCTAssertTrue(newFolder.waitForExistence(timeout: 10))
        newFolder.tap()
        let name = app.alerts.textFields["Folder Name"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        name.tap()
        name.typeText("Research")
        app.alerts.buttons["Save"].tap()
        let folder = app.buttons["Research"]
        XCTAssertTrue(folder.waitForExistence(timeout: 10))
        XCTAssertEqual(folder.value as? String, "Expanded")
        folder.tap()
        let collapsed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Collapsed"), object: folder)
        XCTAssertEqual(XCTWaiter.wait(for: [collapsed], timeout: 10), .completed)
    }
}
