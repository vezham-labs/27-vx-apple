import Foundation
import Testing
@testable import BrowserCore

struct RouteRuleTests {
    @Test func matchesWholeHostsAndPathSegments() throws {
        let destination = UUID()
        let pathRule = RouteRule(pattern: "example.com/work", spaceID: destination)
        let hostRule = RouteRule(pattern: "example.com", spaceID: UUID())
        let rules = [hostRule, pathRule]
        let destinations: Set<UUID> = [destination, hostRule.spaceID]
        let child = try #require(URL(string: "https://team.example.com/work/notes"))
        let sibling = try #require(URL(string: "https://example.com/workshop"))
        let lookalike = try #require(URL(string: "https://otherexample.com/work"))
        #expect(RouteRule.bestMatch(for: child, rules: rules, destinations: destinations) == pathRule)
        #expect(RouteRule.bestMatch(for: child, rules: rules, destinations: [hostRule.spaceID]) == hostRule)
        #expect(RouteRule.bestMatch(for: sibling, rules: rules, destinations: destinations) == hostRule)
        #expect(RouteRule.bestMatch(for: lookalike, rules: rules, destinations: destinations) == nil)
    }

    @Test func validatesInputAndKeepsSignInFlowsInPlace() throws {
        #expect(RouteRule.normalizedPattern(" HTTPS://WWW.Example.com/Work/ ") == "example.com/work")
        #expect(RouteRule.normalizedPattern("example.com/a?b=2") == nil)
        #expect(RouteRule.normalizedPattern("https://name@example.com") == nil)
        let rule = RouteRule(pattern: "github.com", spaceID: UUID())
        let signIn = try #require(URL(string: "https://github.com/login/device"))
        #expect(RouteRule.bestMatch(for: signIn, rules: [rule], destinations: [rule.spaceID]) == nil)
    }

    @Test func olderSettingsRetainTheirDestinationAndDefaultToNoRules() throws {
        let id = UUID()
        let data = Data("{\"externalLinksSpaceID\":\"\(id)\"}".utf8)
        var settings = try JSONDecoder().decode(BrowserSettings.self, from: data)
        #expect(settings.externalLinksSpaceID == id)
        #expect(!settings.linkRoutingEnabled)
        #expect(settings.linkRoutingRules.isEmpty)
        settings.linkRoutingEnabled = true
        settings.linkRoutingRules = [RouteRule(pattern: "example.com/work", spaceID: id)]
        let encoded = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(BrowserSettings.self, from: encoded) == settings)
    }
}
