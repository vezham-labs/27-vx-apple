import AppKit
import SwiftUI
import Observation
import BrowserCore

/// Ark's local freeform boards. Data and captures stay on this Mac for now.
struct EaselCard: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable { case page, note, image }
    let id: UUID
    var kind: Kind
    var x: Double
    var y: Double
    var title: String
    var text: String
    var url: URL?
    var imageName: String?

    init(id: UUID = UUID(), kind: Kind, x: Double, y: Double, title: String, text: String = "", url: URL? = nil, imageName: String? = nil) {
        self.id = id; self.kind = kind; self.x = x; self.y = y
        self.title = title; self.text = text; self.url = url; self.imageName = imageName
    }
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

    @discardableResult func addClipboardImage(to boardID: UUID, pasteboard: NSPasteboard = .general) -> Bool {
        guard let data = pasteboard.data(forType: .png), data.count <= 15 * 1_024 * 1_024,
              let i = boards.firstIndex(where: { $0.id == boardID }) else { return false }
        do {
            try FileManager.default.createDirectory(at: imageDirectory, withIntermediateDirectories: true)
            let name = "\(UUID().uuidString).png"
            try data.write(to: imageDirectory.appending(path: name), options: .atomic)
            let (x, y) = placement(after: boards[i].cards.count)
            boards[i].cards.append(EaselCard(kind: .image, x: x, y: y, title: "Capture", imageName: name))
            save(); return true
        } catch { return false }
    }

    func updateText(_ text: String, for cardID: UUID, in boardID: UUID) {
        update(cardID, in: boardID) { $0.text = text }
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
            Menu {
                Button("Add Note", systemImage: "note.text") { _ = store.addNote(to: boardID) }
                Button("Add Clipboard Image", systemImage: "photo") {
                    if !store.addClipboardImage(to: boardID) { browser.showToast("Image is too large to add") }
                }
                    .disabled(NSPasteboard.general.data(forType: .png) == nil)
            } label: { Label("Add to Easel", systemImage: "plus") }.buttonStyle(.borderedProminent)
        }.padding(.horizontal, 22).padding(.vertical, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "rectangle.on.rectangle.angled").font(.system(size: 30)).foregroundStyle(.secondary)
            Text("A space for your ideas").font(.system(size: 19, weight: .semibold))
            Text("Add a note or image. Right-click a page and choose Add to Easel to save it here.")
                .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 390)
        }.padding(28).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18)).allowsHitTesting(false)
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

    init(card: EaselCard, boardID: UUID, store: EaselStore, open: @escaping (URL) -> Void) {
        self.card = card; self.boardID = boardID; self.store = store; self.open = open
        _noteText = State(initialValue: card.text)
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
        .frame(width: card.kind == .image ? 320 : 260, height: card.kind == .image ? 230 : 190)
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
        }
    }

    private var symbol: String {
        switch card.kind { case .page: "link"; case .note: "note.text"; case .image: "photo" }
    }
}
