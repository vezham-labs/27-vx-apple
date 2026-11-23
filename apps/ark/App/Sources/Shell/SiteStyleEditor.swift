import SwiftUI
import BrowserCore

struct SiteStyleEditor: View {
    @Environment(BrowserState.self) private var browser
    let host: String
    @State var css: String
    @State private var saveFailed = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text(host).foregroundStyle(.secondary)
                TextEditor(text: $css)
                    .font(.body.monospaced())
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityLabel("Custom CSS")
                    .padding(4)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
                Button("Clear CSS") { css = "" }
                    .disabled(css.isEmpty)
                if saveFailed {
                    Text("Couldn’t save the site style.").font(.footnote).foregroundStyle(.red)
                }
            }
            .padding()
            .navigationTitle("Site Style")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { browser.siteStyleHost = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do { try browser.saveSiteStyle(css, for: host) }
                        catch { saveFailed = true }
                    }
                }
            }
        }
    }
}
