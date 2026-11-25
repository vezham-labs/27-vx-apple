import AppKit
import SwiftUI
import Observation
import BrowserCore
import UniformTypeIdentifiers

/// Ark's local freeform boards. Data and captures stay on this Mac for now.
struct EaselCard: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable { case page, note, image, drawing }
    let id: UUID
    var kind: Kind
    var x: Double
    var y: Double
    var title: String
    var text: String
    var url: URL?
    var imageName: String?
    var strokes: [[EaselPoint]]?

    init(id: UUID = UUID(), kind: Kind, x: Double, y: Double, title: String, text: String = "", url: URL? = nil,
         imageName: String? = nil, strokes: [[EaselPoint]]? = nil) {
        self.id = id; self.kind = kind; self.x = x; self.y = y
        self.title = title; self.text = text; self.url = url; self.imageName = imageName; self.strokes = strokes
    }
}

struct EaselPoint: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
}

struct EaselBoard: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var cards: [EaselCard]
    init(id: UUID = UUID(), name: String, cards: [EaselCard] = []) {
        self.id = id; self.name = name; self.cards = cards
    }
}

@MainActor @Observable
final class EaselStore {
    private(set) var boards: [EaselBoard]
    private let fileURL: URL
    private let imageDirectory: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
        imageDirectory = fileURL.deletingLastPathComponent().appending(path: "EaselImages", directoryHint: .isDirectory)
        if let data = try? Data(contentsOf: fileURL), let saved = try? JSONDecoder().decode([EaselBoard].self, from: data), !saved.isEmpty {
            boards = saved
        } else {
            boards = [EaselBoard(name: "Ideas")]
        }
    }

    var firstBoard: EaselBoard? { boards.first }

    private func placement(after count: Int) -> (Double, Double) {
        (190 + Double(count % 4) * 290, 150 + Double(count / 4) * 240)
    }

    @discardableResult func addBoard() -> EaselBoard {
        let board = EaselBoard(name: "New Easel")
        boards.append(board); save(); return board
    }

    func renameBoard(_ id: UUID, to name: String) {
        guard let i = boards.firstIndex(where: { $0.id == id }) else { return }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        boards[i].name = String(name.prefix(80)); save()
    }

    @discardableResult func addPage(_ url: URL, title: String, to boardID: UUID) -> Bool {
        guard url.scheme?.hasPrefix("http") == true, let i = boards.firstIndex(where: { $0.id == boardID }) else { return false }
        let (x, y) = placement(after: boards[i].cards.count)
        boards[i].cards.append(EaselCard(kind: .page, x: x, y: y,
                                         title: title.isEmpty ? (url.host() ?? url.absoluteString) : title, url: url))
        save(); return true
    }

    @discardableResult func addNote(to boardID: UUID) -> UUID? {
        guard let i = boards.firstIndex(where: { $0.id == boardID }) else { return nil }
        let (x, y) = placement(after: boards[i].cards.count)
        let card = EaselCard(kind: .note, x: x, y: y, title: "Note")
        boards[i].cards.append(card); save(); return card.id
    }

    @discardableResult func addDrawing(to boardID: UUID) -> UUID? {
        guard let i = boards.firstIndex(where: { $0.id == boardID }) else { return nil }
        let (x, y) = placement(after: boards[i].cards.count)
        let card = EaselCard(kind: .drawing, x: x, y: y, title: "Doodle", strokes: [])
        boards[i].cards.append(card); save(); return card.id
    }

    @discardableResult func addClipboardImage(to boardID: UUID, pasteboard: NSPasteboard = .general) -> Bool {
        guard let data = pasteboard.data(forType: .png) else { return false }
        return addImage(data, title: "Capture", to: boardID)
    }

    @discardableResult func addImage(_ data: Data, title: String, to boardID: UUID) -> Bool {
        guard data.count <= 15 * 1_024 * 1_024, NSImage(data: data) != nil,
              let i = boards.firstIndex(where: { $0.id == boardID }) else { return false }
        do {
            try FileManager.default.createDirectory(at: imageDirectory, withIntermediateDirectories: true)
            let name = "\(UUID().uuidString).png"
            try data.write(to: imageDirectory.appending(path: name), options: .atomic)
            let (x, y) = placement(after: boards[i].cards.count)
            boards[i].cards.append(EaselCard(kind: .image, x: x, y: y, title: title, imageName: name))
            save(); return true
        } catch { return false }
    }

    func updateText(_ text: String, for cardID: UUID, in boardID: UUID) {
        update(cardID, in: boardID) { $0.text = text }
    }

    func updateStrokes(_ strokes: [[EaselPoint]], for cardID: UUID, in boardID: UUID) {
        update(cardID, in: boardID) { $0.strokes = strokes }
    }

    func move(_ cardID: UUID, in boardID: UUID, by delta: CGSize) {
        update(cardID, in: boardID) {
            $0.x = min(2200, max(130, $0.x + delta.width))
            $0.y = min(1650, max(105, $0.y + delta.height))
        }
    }

    func remove(_ cardID: UUID, from boardID: UUID) {
        guard let b = boards.firstIndex(where: { $0.id == boardID }),
              let c = boards[b].cards.firstIndex(where: { $0.id == cardID }) else { return }
        let card = boards[b].cards.remove(at: c)
        if let name = card.imageName { try? FileManager.default.removeItem(at: imageDirectory.appending(path: name)) }
        save()
    }

    func imageURL(named name: String?) -> URL? {
        guard let name else { return nil }
        let url = imageDirectory.appending(path: name).standardizedFileURL
        return url.deletingLastPathComponent() == imageDirectory.standardizedFileURL ? url : nil
    }

    @discardableResult func exportPNG(_ boardID: UUID, to url: URL) -> Bool {
        guard let board = boards.first(where: { $0.id == boardID }) else { return false }
        let renderer = ImageRenderer(content: EaselExportCanvas(board: board, store: self))
        renderer.scale = 1
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return false }
        do {
            try png.write(to: url, options: .atomic)
            return true
        } catch { return false }
    }

    func exportAllAsZip(to outputURL: URL) async -> Bool {
        let pages = boards.enumerated().map { index, board in
            EaselArchivePage(fileName: "easel-\(index + 1).html", html: Self.archiveHTML(board, imageURL: { self.imageURL(named: $0) }))
        }
        let assets = boards.flatMap(\.cards).compactMap { card -> EaselArchiveAsset? in
            guard card.kind == .image, let source = imageURL(named: card.imageName) else { return nil }
            return EaselArchiveAsset(source: source, name: "\(card.id.uuidString).png")
        }
        let names = boards.map(\.name)
        return await Task.detached(priority: .userInitiated) {
            EaselArchiveExporter.createZip(pages: pages, assets: assets, boardNames: names, to: outputURL)
        }.value
    }

    private static func archiveHTML(_ board: EaselBoard, imageURL: (String?) -> URL?) -> String {
        let contents = board.cards.map { card -> String in
            let width = card.kind == .image || card.kind == .drawing ? 320 : 260
            let height = card.kind == .image || card.kind == .drawing ? 230 : 190
            let inner: String
            switch card.kind {
            case .page:
                if let url = card.url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                    inner = "<a href=\"\(escapeHTML(url.absoluteString))\">\(escapeHTML(card.title))</a><p>\(escapeHTML(url.absoluteString))</p>"
                } else { inner = "<p>\(escapeHTML(card.title))</p>" }
            case .note:
                inner = "<p class=\"note\">\(escapeHTML(card.text).replacingOccurrences(of: "\\n", with: "<br>"))</p>"
            case .image:
                inner = imageURL(card.imageName).map { _ in "<img src=\"assets/\(card.id.uuidString).png\" alt=\"\(escapeHTML(card.title))\">" } ?? "<p>Image unavailable</p>"
            case .drawing:
                let paths = (card.strokes ?? []).compactMap { stroke -> String? in
                    guard let first = stroke.first else { return nil }
                    let points = ([first] + stroke.dropFirst()).enumerated().map { index, point in
                        "\(index == 0 ? "M" : "L")\(String(format: "%.1f", point.x)) \(String(format: "%.1f", point.y))"
                    }.joined(separator: " ")
                    return "<path d=\"\(points)\"/>"
                }.joined()
                inner = "<svg viewBox=\"0 0 296 154\" aria-label=\"Doodle\">\(paths)</svg>"
            }
            return "<article style=\"left:\(card.x - Double(width) / 2)px;top:\(card.y - Double(height) / 2)px;width:\(width)px;height:\(height)px\"><h2>\(escapeHTML(card.title))</h2>\(inner)</article>"
        }.joined(separator: "\n")
        return """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>\(escapeHTML(board.name))</title><style>
        *{box-sizing:border-box}body{margin:0;width:2400px;height:1800px;position:relative;background:#f4f4f4;color:#222;font:14px -apple-system,BlinkMacSystemFont,sans-serif;background-image:radial-gradient(#bbb 1px,transparent 1px);background-size:28px 28px}article{position:absolute;padding:12px;border:1px solid #ddd;border-radius:12px;background:white;box-shadow:0 4px 18px #0002;overflow:hidden}h2{font-size:12px;margin:0 0 8px}p{line-height:1.5;overflow-wrap:anywhere}a{color:#1565c0}img{width:100%;height:calc(100% - 28px);object-fit:contain}svg{width:100%;height:calc(100% - 28px);fill:none;stroke:#222;stroke-width:3;stroke-linecap:round;stroke-linejoin:round}.note{white-space:pre-wrap}
        </style></head><body>\(contents)</body></html>
        """
    }

    nonisolated fileprivate static func escapeHTML(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private func update(_ cardID: UUID, in boardID: UUID, _ change: (inout EaselCard) -> Void) {
        guard let b = boards.firstIndex(where: { $0.id == boardID }),
              let c = boards[b].cards.firstIndex(where: { $0.id == cardID }) else { return }
        change(&boards[b].cards[c]); save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(boards) else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch { }
    }
}

private struct EaselArchivePage: Sendable { let fileName: String; let html: String }
private struct EaselArchiveAsset: Sendable { let source: URL; let name: String }

private enum EaselArchiveExporter {
    static func createZip(pages: [EaselArchivePage], assets: [EaselArchiveAsset], boardNames: [String], to outputURL: URL) -> Bool {
        let work = FileManager.default.temporaryDirectory.appending(path: "Ark-Easels-\(UUID().uuidString)", directoryHint: .isDirectory)
        let root = work.appending(path: "Ark Easels", directoryHint: .isDirectory)
        let assetDirectory = root.appending(path: "assets", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: work) }
        do {
            try FileManager.default.createDirectory(at: assetDirectory, withIntermediateDirectories: true)
            let links = zip(boardNames.indices, pages).map { index, page in
                "<li><a href=\"\(page.fileName)\">\(EaselStore.escapeHTML(boardNames[index]))</a></li>"
            }.joined(separator: "\n")
            let index = "<!doctype html><html><meta charset=\"utf-8\"><title>Ark Easels</title><h1>Ark Easels</h1><ul>\(links)</ul></html>"
            try Data(index.utf8).write(to: root.appending(path: "index.html"), options: .atomic)
            for page in pages { try Data(page.html.utf8).write(to: root.appending(path: page.fileName), options: .atomic) }
            for asset in assets { try FileManager.default.copyItem(at: asset.source, to: assetDirectory.appending(path: asset.name)) }
            let process = Process()
            process.executableURL = URL(filePath: "/usr/bin/ditto")
            process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", root.path, outputURL.path]
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch { return false }
    }
}

struct EaselView: View {
    @Environment(Browser.self) private var browser
    @Bindable var store: EaselStore
    @State private var boardID: UUID
    @State private var renaming = false
    @State private var nameDraft = ""

    init(store: EaselStore) {
        self.store = store
        _boardID = State(initialValue: store.firstBoard?.id ?? UUID())
    }

    private var board: EaselBoard? { store.boards.first(where: { $0.id == boardID }) ?? store.firstBoard }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
            if let board {
                ScrollView([.horizontal, .vertical]) {
                    ZStack(alignment: .topLeading) {
                        EaselGrid()
                        ForEach(board.cards) { card in
                            EaselCardView(card: card, boardID: board.id, store: store) { url in browser.newTab(url: url) }
                                .position(x: card.x, y: card.y)
                        }
                    }.frame(width: 2400, height: 1800, alignment: .topLeading)
                }
                .background(Color(nsColor: .underPageBackgroundColor))
                .overlay { if board.cards.isEmpty { emptyState } }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .alert("Rename Easel", isPresented: $renaming) {
            TextField("Name", text: $nameDraft)
            Button("Cancel", role: .cancel) { }
            Button("Save") { store.renameBoard(boardID, to: nameDraft) }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button { browser.openLibrary() } label: { Label("Library", systemImage: "chevron.left") }.buttonStyle(.plain)
            Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1, height: 22)
            Menu {
                ForEach(store.boards) { item in Button(item.name) { boardID = item.id } }
                Divider()
                Button("New Easel", systemImage: "plus") { boardID = store.addBoard().id }
                Button("Rename Easel…", systemImage: "pencil") { nameDraft = board?.name ?? ""; renaming = true }
            } label: {
                Label(board?.name ?? "Easel", systemImage: "rectangle.on.rectangle.angled").font(.system(size: 14, weight: .semibold))
            }.menuStyle(.button).buttonStyle(.plain)
            Spacer()
            Button { exportBoard() } label: { Label("Export PNG…", systemImage: "square.and.arrow.up") }
                .buttonStyle(.plain)
                .disabled(board == nil)
            Button { exportAllBoards() } label: { Label("Export All…", systemImage: "archivebox") }
                .buttonStyle(.plain)
                .disabled(store.boards.isEmpty)
            Menu {
                Button("Add Note", systemImage: "note.text") { _ = store.addNote(to: boardID) }
                Button("Add Doodle", systemImage: "scribble") { _ = store.addDrawing(to: boardID) }
                Button("Capture Current Page", systemImage: "viewfinder") {
                    browser.captureCurrentPage(toEasel: boardID)
                }
                    .disabled(browser.currentTab?.isPrivate != false || browser.currentTab?.url == nil || browser.isCapturingPage)
                Button("Add Clipboard Image", systemImage: "photo") {
                    if !store.addClipboardImage(to: boardID) { browser.showToast("Image is too large to add") }
                }
                    .disabled(NSPasteboard.general.data(forType: .png) == nil)
            } label: { Label("Add to Easel", systemImage: "plus") }.buttonStyle(.borderedProminent)
        }.padding(.horizontal, 22).padding(.vertical, 12)
    }

    private func exportBoard() {
        guard let board, let window = browser.nsWindow, window.attachedSheet == nil else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = board.name + ".png"
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            browser.showToast(store.exportPNG(board.id, to: url) ? "Easel exported" : "Couldn’t export Easel")
        }
    }

    private func exportAllBoards() {
        guard let window = browser.nsWindow, window.attachedSheet == nil else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "zip") ?? .archive]
        panel.nameFieldStringValue = "Ark Easels.zip"
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                browser.showToast(await store.exportAllAsZip(to: url) ? "Easels exported" : "Couldn’t export Easels")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "rectangle.on.rectangle.angled").font(.system(size: 30)).foregroundStyle(.secondary)
            Text("A space for your ideas").font(.system(size: 19, weight: .semibold))
            Text("Add a note, doodle, or capture. Right-click a page and choose Add to Easel to save it here.")
                .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 390)
        }.padding(28).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18)).allowsHitTesting(false)
    }
}

/// Static, interaction-free rendering used for a lossless single-board PNG export.
private struct EaselExportCanvas: View {
    let board: EaselBoard
    let store: EaselStore

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(nsColor: .underPageBackgroundColor)
            EaselGrid()
            ForEach(board.cards) { card in
                EaselExportCard(card: card, imageURL: store.imageURL(named: card.imageName))
                    .position(x: card.x, y: card.y)
            }
        }
        .frame(width: 2400, height: 1800)
        .clipped()
    }
}

private struct EaselExportCard: View {
    let card: EaselCard
    let imageURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(card.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            switch card.kind {
            case .page:
                Text(card.url?.absoluteString ?? "").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
            case .note:
                Text(card.text).font(.system(size: 13)).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            case .image:
                if let imageURL, let image = NSImage(contentsOf: imageURL) {
                    Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            case .drawing:
                Canvas { context, _ in
                    for stroke in card.strokes ?? [] {
                        guard let first = stroke.first else { continue }
                        var path = Path()
                        path.move(to: CGPoint(x: first.x, y: first.y))
                        for point in stroke.dropFirst() { path.addLine(to: CGPoint(x: point.x, y: point.y)) }
                        context.stroke(path, with: .color(.primary), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    }
                }
            }
        }
        .padding(12)
        .frame(width: card.kind == .image || card.kind == .drawing ? 320 : 260,
               height: card.kind == .image || card.kind == .drawing ? 230 : 190)
        .background(card.kind == .note ? Color.yellow.opacity(0.2) : Color(nsColor: .textBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
    }
}

private struct EaselGrid: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            for x in stride(from: 0.0, through: size.width, by: 28) {
                for y in stride(from: 0.0, through: size.height, by: 28) {
                    path.addEllipse(in: CGRect(x: x, y: y, width: 1.3, height: 1.3))
                }
            }
            context.fill(path, with: .color(.primary.opacity(0.09)))
        }.allowsHitTesting(false)
    }
}

private struct EaselCardView: View {
    let card: EaselCard
    let boardID: UUID
    let store: EaselStore
    let open: (URL) -> Void
    @State private var noteText: String
    @State private var strokes: [[EaselPoint]]
    @State private var draftStroke: [EaselPoint] = []

    init(card: EaselCard, boardID: UUID, store: EaselStore, open: @escaping (URL) -> Void) {
        self.card = card; self.boardID = boardID; self.store = store; self.open = open
        _noteText = State(initialValue: card.text)
        _strokes = State(initialValue: card.strokes ?? [])
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: symbol).foregroundStyle(.secondary)
                Text(card.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 0)
                Button { store.remove(card.id, from: boardID) } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                }.buttonStyle(.plain).help("Remove from Easel")
            }
            .padding(.horizontal, 12).frame(height: 34).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 3).onEnded { store.move(card.id, in: boardID, by: $0.translation) })
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(12)
        }
        .frame(width: card.kind == .image || card.kind == .drawing ? 320 : 260,
               height: card.kind == .image || card.kind == .drawing ? 230 : 190)
        .background(card.kind == .note ? Color.yellow.opacity(0.2) : Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
    }

    @ViewBuilder private var content: some View {
        switch card.kind {
        case .page:
            Button { if let url = card.url { open(url) } } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(card.url?.host() ?? "Saved page").font(.system(size: 13, weight: .medium)).lineLimit(2)
                    Text(card.url?.absoluteString ?? "").font(.system(size: 11, design: .monospaced)).lineLimit(3).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }.buttonStyle(.plain)
        case .note:
            TextEditor(text: $noteText).font(.system(size: 13)).scrollContentBackground(.hidden)
                .onChange(of: noteText) { _, value in store.updateText(value, for: card.id, in: boardID) }
        case .image:
            if let url = store.imageURL(named: card.imageName), let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView("Image Missing", systemImage: "photo", description: Text("This capture is no longer on this Mac."))
            }
        case .drawing:
            Canvas { context, _ in
                for stroke in strokes + (draftStroke.isEmpty ? [] : [draftStroke]) {
                    guard let first = stroke.first else { continue }
                    var path = Path()
                    path.move(to: CGPoint(x: first.x, y: first.y))
                    for point in stroke.dropFirst() { path.addLine(to: CGPoint(x: point.x, y: point.y)) }
                    context.stroke(path, with: .color(.primary), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard draftStroke.count < 4096 else { return }
                    let point = EaselPoint(x: value.location.x, y: value.location.y)
                    if let last = draftStroke.last {
                        let dx = point.x - last.x
                        let dy = point.y - last.y
                        guard dx * dx + dy * dy >= 4 else { return }
                    }
                    draftStroke.append(point)
                }
                .onEnded { _ in
                    guard !draftStroke.isEmpty else { return }
                    strokes.append(draftStroke)
                    draftStroke = []
                    store.updateStrokes(strokes, for: card.id, in: boardID)
                })
        }
    }

    private var symbol: String {
        switch card.kind { case .page: "link"; case .note: "note.text"; case .image: "photo"; case .drawing: "scribble" }
    }
}
