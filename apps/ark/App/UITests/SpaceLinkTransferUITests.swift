import XCTest

@MainActor
final class SpaceLinkTransferUITests: XCTestCase {
    func testSpacesSettingsCanPresentFileExport() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "1", "--posture", "unfolded"]
        app.launch()

        let settings = app.buttons["Settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()

        let importButton = app.buttons["Import Space Links…"]
        let exportMenu = app.buttons["Export Space Links…"]
        for _ in 0..<5 where !exportMenu.isHittable { app.swipeUp() }
        XCTAssertTrue(importButton.isHittable)
        XCTAssertTrue(exportMenu.isHittable)
        exportMenu.staticTexts["Export Space Links…"].tap()
        let personal = app.descendants(matching: .any)["Export Personal"].firstMatch
        XCTAssertTrue(personal.waitForExistence(timeout: 5))
        personal.tap()
        XCTAssertTrue(app.buttons["Cancel"].firstMatch.waitForExistence(timeout: 10))
    }
}
