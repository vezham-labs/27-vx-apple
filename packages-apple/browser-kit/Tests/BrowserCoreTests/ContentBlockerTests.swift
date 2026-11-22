#if canImport(WebKit)
import Testing
import WebKit
@testable import BrowserCore

@MainActor
@Test func defaultContentBlockingWorksWithoutAnUpdateServer() async throws {
    let blocker = ContentBlocker.shared

    #expect(!blocker.needsUpdate)
    let updates = try await blocker.update(groups: Set(FilterGroup.allCases))
    #expect(updates.isEmpty)

    let lists = await blocker.lists(for: Set(FilterGroup.allCases), allowlist: [])
    #expect(lists.count == 1)
}
#endif
