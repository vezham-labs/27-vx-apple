import Foundation
import Observation

struct Todo: Codable, Identifiable, Equatable {
  var resource_id: String
  var title: String
  var done = false
  var deleted = false
  var client_created_at: String
  var version = 0
  var server_created_at: String?
  var id: String { resource_id }
}

struct Pending: Codable {
  var todo: Todo
  var operation_id: String
  var base_version: Int
}
struct Snapshot: Codable {
  var rows: [String: Todo] = [:]
  var queue: [Pending] = []
  var conflicts: [String: Todo] = [:]
  var cursor = 0
  var visible: [Todo] {
    var values = rows
    for op in queue { values[op.todo.id] = op.todo }
    return values.values.filter { !$0.deleted }.sorted {
      $0.client_created_at > $1.client_created_at
    }
  }
  mutating func merge(_ todo: Todo) {
    if todo.version > (rows[todo.id]?.version ?? 0) { rows[todo.id] = todo }
  }
}
struct Page: Decodable {
  var items: [Todo]
  var more: Bool
  var cursor: Int
}
struct Conflict: Decodable { var current: Todo }

@MainActor @Observable final class TodoStore {
  private(set) var state = Snapshot()
  var status = ""
  private var busy = false
  private var readable = true
  let file: URL
  let api: URL
  init(file: URL, api: URL) {
    self.file = file
    self.api = api
    if FileManager.default.fileExists(atPath: file.path) {
      do { state = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: file)) } catch {
        readable = false
        status = "Could not read saved todos."
      }
    }
  }
  func commit(_ body: (inout Snapshot) -> Void) throws {
    guard readable else { throw CocoaError(.fileReadCorruptFile) }
    var next = state
    body(&next)
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder().encode(next).write(to: file, options: .atomic)
    state = next
  }
  func add(_ title: String) throws {
    try save(
      Todo(
        resource_id: UUID().uuidString.lowercased(), title: title,
        client_created_at: Date().ISO8601Format()))
  }
  func save(_ input: Todo) throws {
    var row = input
    row.title = row.title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !row.title.isEmpty, row.title.unicodeScalars.count <= 200 else {
      throw NSError(
        domain: "Todo", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Use a title of 1–200 characters."])
    }
    let base =
      state.queue.last(where: { $0.todo.id == row.id })?.todo.version ?? state.rows[row.id]?.version
      ?? 0
    row.version = base + 1
    try commit {
      $0.queue.append(
        Pending(todo: row, operation_id: UUID().uuidString.lowercased(), base_version: base))
    }
  }
  func acceptServer(_ id: String) throws {
    try commit { s in
      s.queue.removeAll { $0.todo.id == id }
      s.conflicts.removeValue(forKey: id)
    }
  }
  private func request(_ path: String, body: Data? = nil) async throws -> (Data, Int) {
    var req = URLRequest(
      url: URL(string: path, relativeTo: api)!, cachePolicy: .reloadIgnoringLocalCacheData,
      timeoutInterval: 8)
    if let body {
      req.httpMethod = "POST"
      req.httpBody = body
      req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    let (data, response) = try await URLSession.shared.data(for: req)
    return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
  }
  func sync() async {
    guard readable, !busy else { return }
    busy = true
    defer { busy = false }
    do {
      while let op = state.queue.first(where: { state.conflicts[$0.todo.id] == nil }) {
        var dict =
          try JSONSerialization.jsonObject(with: JSONEncoder().encode(op.todo)) as! [String: Any]
        dict["operation_id"] = op.operation_id
        dict["base_version"] = op.base_version
        let (data, code) = try await request(
          "mutations", body: JSONSerialization.data(withJSONObject: dict))
        if code == 409 {
          let current = try JSONDecoder().decode(Conflict.self, from: data).current
          try commit {
            $0.merge(current)
            $0.conflicts[op.todo.id] = current
          }
          continue
        }
        guard code == 200 else { throw URLError(.badServerResponse) }
        let saved = try JSONDecoder().decode(Todo.self, from: data)
        try commit {
          $0.merge(saved)
          $0.queue.removeAll { $0.operation_id == op.operation_id }
        }
      }
      while true {
        let (data, code) = try await request("changes?after=\(state.cursor)")
        guard code == 200 else { throw URLError(.badServerResponse) }
        let page = try JSONDecoder().decode(Page.self, from: data)
        if !page.items.isEmpty {
          try commit { s in
            for t in page.items { s.merge(t) }
            s.cursor = page.cursor
          }
        }
        if !page.more { break }
      }
      status = ""
    } catch { status = "Sync unavailable · changes stay on this device" }
  }
}
