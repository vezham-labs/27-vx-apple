import BrowserCore
import SwiftUI

struct SpaceRoutingSettings: View {
    @Environment(BrowserState.self) private var browser
    @State private var pattern = ""
    @State private var destination: UUID?

    var body: some View {
        @Bindable var browser = browser
        Form {
            Section {
                Toggle("Open sites in their Space", isOn: $browser.settings.linkRoutingEnabled)
            } footer: {
                Text("Rules apply to new tabs and links from other apps. The most specific address wins.")
            }

            Section("Rules") {
                ForEach($browser.settings.linkRoutingRules) { $rule in
                    Picker(rule.pattern, selection: $rule.spaceID) {
                        ForEach(browser.regularSpaces) { space in
                            Text(space.name).tag(space.id)
                        }
                    }
                }
                .onDelete { browser.settings.linkRoutingRules.remove(atOffsets: $0) }

                TextField("example.com or example.com/work", text: $pattern)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Site or path")
                Picker("Destination", selection: $destination) {
                    Text("Choose a Space").tag(UUID?.none)
                    ForEach(browser.regularSpaces) { space in
                        Text(space.name).tag(Optional(space.id))
                    }
                }
                Button("Save Rule", action: saveRule)
                    .disabled(destination == nil || RouteRule.normalizedPattern(pattern) == nil)
            }
        }
        .navigationTitle("Space Routing")
        .onAppear { destination = destination ?? browser.regularSpaces.first?.id }
    }

    private func saveRule() {
        guard let pattern = RouteRule.normalizedPattern(pattern), let destination,
              browser.regularSpaces.contains(where: { $0.id == destination }) else { return }
        if let existing = browser.settings.linkRoutingRules.firstIndex(where: { $0.pattern == pattern }) {
            browser.settings.linkRoutingRules[existing].spaceID = destination
        } else {
            browser.settings.linkRoutingRules.append(RouteRule(pattern: pattern, spaceID: destination))
        }
        self.pattern = ""
    }
}
