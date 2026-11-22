import Foundation

@main struct Smoke {
  @MainActor static func main() async throws {
    let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let api = URL(
      string: ProcessInfo.processInfo.environment["TODO_TEST_API"] ?? "http://127.0.0.1:47832/api/")!
    let file = directory.appending(path: "local.json")
    let first = TodoStore(file: file, api: api)
    try first.add("Swift offline")
    let client = TodoStore(file: file, api: api)
    precondition(
      client.state.visible.first?.title == "Swift offline" && client.state.queue.count == 1)
    let id = client.state.visible[0].id
    await client.sync()
    precondition(client.state.queue.isEmpty, "Start the test API first")
    let other = TodoStore(file: directory.appending(path: "other.json"), api: api)
    await other.sync()
    var item = other.state.rows[id]!
    item.title = "Changed on second device"
    try other.save(item)
    await other.sync()
    var stale = client.state.rows[id]!
    stale.title = "My offline title"
    try client.save(stale)
    await client.sync()
    precondition(client.state.conflicts[id]?.title == item.title)
    try client.acceptServer(id)
    item = client.state.rows[id]!
    item.done = true
    try client.save(item)
    await client.sync()
    await other.sync()
    precondition(other.state.rows[id]?.done == true)
    item.deleted = true
    try other.save(item)
    await other.sync()
    await client.sync()
    precondition(client.state.rows[id]?.deleted == true)
    if let expected = ProcessInfo.processInfo.environment["TODO_WEB_TITLE"] {
      guard var web = client.state.visible.first(where: { $0.title == expected }) else {
        fatalError("Missing browser todo")
      }
      web.done = true
      try client.save(web)
      await client.sync()
      precondition(client.state.queue.isEmpty)
    }
    print("Passed offline restart, sync, conflicts, completion and deletion.")
  }
}
