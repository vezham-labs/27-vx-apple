import SwiftUI

@main struct TodoMacApp: App {
  @State private var store = TodoStore(
    file: URL.applicationSupportDirectory.appending(path: "vx-todos/workspace.json"),
    api: URL(string: "http://127.0.0.1:47831/api/")!)
  var body: some Scene {
    WindowGroup { TodoScreen(store: store) }
  }
}
