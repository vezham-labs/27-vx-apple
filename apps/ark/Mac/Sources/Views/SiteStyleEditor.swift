import SwiftUI
import BrowserCore

struct SiteStyleEditor: View {
    @Environment(Browser.self) private var browser
    let host: String
    @State var css: String
    @State var hiddenElements: [HiddenSiteElement]
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
            if !hiddenElements.isEmpty {
                HStack {
                    Text("Hidden elements").font(.subheadline.weight(.medium))
                    Spacer()
                    Button("Restore All") {
                        do {
                            try browser.restoreAllSiteElements(for: host)
                            hiddenElements = []
                            browser.previewSiteElement(nil)
                            saveFailed = false
                        } catch { saveFailed = true }
                    }
                }
                ScrollView {
                    ForEach(hiddenElements) { element in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(element.label).lineLimit(1)
                                if let note = element.note {
                                    Text(note).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            Spacer()
                            Button("Restore") {
                                do {
                                    try browser.restoreSiteElement(element.selector, for: host)
                                    hiddenElements.removeAll { $0.selector == element.selector }
                                    saveFailed = false
                                } catch { saveFailed = true }
                            }
                        }
                        .onHover { browser.previewSiteElement($0 ? element.selector : nil) }
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
        .onDisappear { browser.previewSiteElement(nil) }
    }
}
