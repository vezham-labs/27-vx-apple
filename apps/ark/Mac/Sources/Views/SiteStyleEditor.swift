import SwiftUI

struct SiteStyleEditor: View {
    @Environment(Browser.self) private var browser
    let host: String
    @State var css: String
    @State var hiddenSelectors: [String]
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
            if !hiddenSelectors.isEmpty {
                Text("Hidden elements").font(.subheadline.weight(.medium))
                ScrollView {
                    ForEach(hiddenSelectors, id: \.self) { selector in
                        HStack {
                            Text(selector).font(.caption.monospaced()).lineLimit(1)
                            Spacer()
                            Button("Restore") {
                                do {
                                    try browser.restoreSiteElement(selector, for: host)
                                    hiddenSelectors.removeAll { $0 == selector }
                                    saveFailed = false
                                } catch { saveFailed = true }
                            }
                            .accessibilityLabel("Restore \(selector)")
                        }
                    }
                }
                .frame(maxHeight: 108)
            }
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
