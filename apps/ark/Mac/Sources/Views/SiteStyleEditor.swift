import SwiftUI
import AppKit
import BrowserCore

struct SiteStyleEditor: View {
    @Environment(Browser.self) private var browser
    let host: String
    @State var css: String
    @State var hiddenElements: [HiddenSiteElement]
    @State var font: SiteStyleFont
    @State var accent: String?
    @State private var saveFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Boosts").font(.headline)
            Text(host).foregroundStyle(.secondary)
            Picker("Page font", selection: $font) {
                ForEach(SiteStyleFont.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            ColorPicker("Accent color", selection: accentColor)
            Text("Optional. Ark applies this colour to links, controls, and selections on this site only.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if accent != nil {
                Button("Remove accent", role: .destructive) { accent = nil }
                    .buttonStyle(.plain)
            }
            TextEditor(text: $css)
                .font(.body.monospaced())
                .accessibilityLabel("Custom CSS")
                .border(.quaternary)
                .frame(minHeight: 180)
            Text("Customize this site with a font and CSS. Select Original and clear the editor to remove your changes.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !hiddenElements.isEmpty {
                HStack {
                    Text("Changed elements").font(.subheadline.weight(.medium))
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
                                Text(element.shape == nil ? "Hidden" : "Moved or resized")
                                    .font(.caption2).foregroundStyle(.secondary)
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
                Text("Couldn’t save these Boosts.").font(.caption).foregroundStyle(.red)
            }
            HStack {
                Button("Import…", action: browser.importSiteStyle)
                Button("Export…") { browser.exportSiteStyle(for: host) }
                Spacer()
                Button("Cancel") { browser.closeSiteStyleEditor() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    do { try browser.saveSiteStyle(css, font: font, accent: accent, for: host) }
                    catch { saveFailed = true }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onDisappear { browser.previewSiteElement(nil) }
    }

    private var accentColor: Binding<Color> {
        Binding(
            get: {
                guard let accent, let color = NSColor(hex: accent) else { return .accentColor }
                return Color(nsColor: color)
            },
            set: { value in
                guard let color = NSColor(value).usingColorSpace(.sRGB) else { return }
                accent = String(format: "#%02X%02X%02X", Int((color.redComponent * 255).rounded()),
                                Int((color.greenComponent * 255).rounded()), Int((color.blueComponent * 255).rounded()))
            }
        )
    }
}

private extension NSColor {
    convenience init?(hex: String) {
        guard let normalized = SiteStyles.normalizedAccent(hex) else { return nil }
        let value = String(normalized.dropFirst())
        guard let rgb = UInt32(value, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((rgb >> 16) & 0xff) / 255,
                  green: CGFloat((rgb >> 8) & 0xff) / 255,
                  blue: CGFloat(rgb & 0xff) / 255, alpha: 1)
    }
}
