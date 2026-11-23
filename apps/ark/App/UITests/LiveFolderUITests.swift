import Foundation
import Network
import XCTest

@MainActor
final class LiveFolderUITests: XCTestCase {
    func testAddsFeedAndOpensArticleFromTabGallery() throws {
        continueAfterFailure = false
        let listener = try FeedFixture.listener()
        defer { listener.cancel() }
        let ready = expectation(description: "Feed is listening on loopback")
        listener.stateUpdateHandler = { state in
            if case .ready = state { ready.fulfill() }
        }
        listener.start(queue: FeedFixture.queue)
        wait(for: [ready], timeout: 10)
        let port = try XCTUnwrap(listener.port)

        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "1", "--posture", "folded"]
        app.launch()
        let tabs = app.buttons["Tabs"].firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 30))
        tabs.tap()

        let newFolder = app.buttons["New Live Folder"]
        XCTAssertTrue(newFolder.waitForExistence(timeout: 10))
        newFolder.tap()
        let address = app.alerts.textFields["Feed or Website Address"].firstMatch
        XCTAssertTrue(address.waitForExistence(timeout: 10))
        address.tap()
        address.typeText("http://127.0.0.1:\(port.rawValue)/feed.xml")
        app.alerts.buttons["Add"].tap()

        XCTAssertTrue(app.buttons["Field Updates"].waitForExistence(timeout: 45))
        let article = app.buttons["Coastal Article"]
        XCTAssertTrue(article.waitForExistence(timeout: 10))
        article.tap()
        XCTAssertTrue(app.webViews.staticTexts["Article opened"].waitForExistence(timeout: 45))
    }
}

private enum FeedFixture {
    static let queue = DispatchQueue(label: "ark.live-folder-uitest")

    static func listener() throws -> NWListener {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { connection in
            connection.start(queue: queue)
            receive(connection)
        }
        return listener
    }

    private static func receive(_ connection: NWConnection, previous: Data = Data()) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4_096) { data, _, complete, error in
            guard let data, error == nil else { connection.cancel(); return }
            let request = previous + data
            guard request.count <= 8_192 else { connection.cancel(); return }
            guard let header = String(data: request, encoding: .utf8), header.contains("\r\n\r\n") else {
                if complete { connection.cancel() } else { receive(connection, previous: request) }
                return
            }
            let type: String
            let body: String
            if header.hasPrefix("GET /feed.xml ") {
                type = "application/rss+xml"
                body = """
                    <rss version="2.0"><channel><title>Field Updates</title>
                    <item><title>Coastal Article</title><link>/article</link></item>
                    </channel></rss>
                    """
            } else if header.hasPrefix("GET /article ") {
                type = "text/html"
                body = "<!doctype html><title>Coastal Article</title><h1>Article opened</h1>"
            } else {
                connection.cancel()
                return
            }
            let response = "HTTP/1.1 200 OK\r\nContent-Type: \(type); charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
        }
    }
}
