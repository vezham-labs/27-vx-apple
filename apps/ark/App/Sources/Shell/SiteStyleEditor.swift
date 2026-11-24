import SwiftUI
import BrowserCore

struct SiteStyleEditor: View {
    @Environment(BrowserState.self) private var browser
    let host: String
    @State var css: String
    @State var hiddenElements: [HiddenSiteElement]
    @State private var previewingSelector: String?
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
                    if !hiddenElements.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Hidden elements").font(.headline)
                                Spacer()
                                Button("Restore All") {
                                    do {
                                        try browser.restoreAllSiteElements(for: host)
                                        hiddenElements = []
                                        previewingSelector = nil
                                        browser.previewSiteElement(nil, for: host)
                                    } catch { saveFailed = true }
                                }
                            }
                            ForEach(hiddenElements) { element in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(element.label).lineLimit(1)
                                        if let note = element.note {
                                            Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                    }
                                    Spacer(minLength: 8)
                                    Button(previewingSelector == element.selector ? "Done" : "Preview") {
                                        let next = previewingSelector == element.selector ? nil : element.selector
                                        previewingSelector = next
                                        browser.previewSiteElement(next, for: host)
                                    }
                                    Button("Restore") {
                                        do {
                                            try browser.restoreSiteElement(element.selector, for: host)
                                            hiddenElements.removeAll { $0.selector == element.selector }
                                            if previewingSelector == element.selector {
                                                previewingSelector = nil
                                                browser.previewSiteElement(nil, for: host)
                                            }
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
        .onDisappear {
            previewingSelector = nil
            browser.previewSiteElement(nil, for: host)
        }
    }
}
