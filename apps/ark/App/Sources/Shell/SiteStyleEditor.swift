import SwiftUI
import BrowserCore

struct SiteStyleEditor: View {
    @Environment(BrowserState.self) private var browser
    let host: String
    @State var css: String
    @State var hiddenSelectors: [String]
    @State private var saveFailed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(host).foregroundStyle(.secondary)
                    TextEditor(text: $css)
                        .font(.body.monospaced())
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .accessibilityLabel("Custom CSS")
                        .padding(4)
                        .frame(minHeight: 180, maxHeight: 280)
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
                    Button("Clear CSS") { css = "" }
                        .disabled(css.isEmpty)
                    if !hiddenSelectors.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Hidden elements").font(.headline)
                                Spacer()
                                Button("Restore All") {
                                    do {
                                        for selector in hiddenSelectors { try browser.restoreSiteElement(selector, for: host) }
                                        hiddenSelectors = []
                                    } catch { saveFailed = true }
                                }
                            }
                            ForEach(hiddenSelectors, id: \.self) { selector in
                                HStack {
                                    Text(selector).font(.caption.monospaced()).lineLimit(1)
                                    Spacer(minLength: 8)
                                    Button("Restore") {
                                        do {
                                            try browser.restoreSiteElement(selector, for: host)
                                            hiddenSelectors.removeAll { $0 == selector }
                                        } catch { saveFailed = true }
                                    }
                                }
                            }
                        }
                    }
                    if saveFailed {
                        Text("Couldn’t save the site style.").font(.footnote).foregroundStyle(.red)
                    }
                }
                .padding()
            }
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
