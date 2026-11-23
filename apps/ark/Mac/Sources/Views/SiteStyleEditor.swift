import SwiftUI

struct SiteStyleEditor: View {
    @Environment(Browser.self) private var browser
    let host: String
    @State var css: String
    @State private var saveFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Site Style").font(.headline)
            Text(host).foregroundStyle(.secondary)
            TextEditor(text: $css)
                .font(.body.monospaced())
                .accessibilityLabel("Custom CSS")
                .border(.quaternary)
                .frame(minHeight: 180)
            Text("Enter CSS for this site. Clear the editor and save to remove the style.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if saveFailed {
                Text("Couldn’t save the site style.").font(.caption).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel") { browser.siteStyleHost = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    do { try browser.saveSiteStyle(css, for: host) }
                    catch { saveFailed = true }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}
