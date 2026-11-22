import SwiftUI

private enum Editor: Identifiable {
  case new
  case edit(Todo)

  var id: String {
    if case .edit(let item) = self { return item.id }
    return "new"
  }
  var title: String {
    if case .edit(let item) = self { return item.title }
    return ""
  }
}

struct TodoScreen: View {
  let store: TodoStore
  @Environment(\.scenePhase) private var phase
  @Environment(\.dynamicTypeSize) private var textSize
  @State private var editor: Editor?
  @State private var error = ""

  var body: some View {
    NavigationStack {
      GeometryReader { geometry in
        let items = store.state.visible
        ScrollView {
          VStack(alignment: .leading, spacing: 20) {
            Text(
              store.status.isEmpty
                ? (store.state.queue.isEmpty ? "Up to date" : "\(store.state.queue.count) pending")
                : store.status
            )
            .font(.subheadline).foregroundStyle(.secondary)
            conflicts
            if items.isEmpty {
              ContentUnavailableView("Your list is empty", systemImage: "checklist")
            } else {
              let active = items.filter { !$0.done }
              let completed = items.filter(\.done)
              let columns = geometry.size.width >= 620 && !textSize.isAccessibilitySize
              let layout =
                columns
                ? AnyLayout(HStackLayout(alignment: .top, spacing: 24))
                : AnyLayout(VStackLayout(alignment: .leading, spacing: 24))
              layout {
                if !active.isEmpty { group("To do", items: active) }
                if !completed.isEmpty { group("Completed", items: completed) }
              }
            }
          }
          .padding().frame(maxWidth: 1100, alignment: .leading)
          .frame(maxWidth: .infinity)
        }
      }
      .navigationTitle("Todos")
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar { actions }
      .preferTodoToolbar()
    }
    .sheet(item: $editor) { selection in
      TodoEditor(selection: selection) { title in
        perform {
          switch selection {
          case .new: try store.add(title)
          case .edit(var item):
            item.title = title
            try store.save(item)
          }
          editor = nil
        }
      }
    }
    .alert(
      "Could not save",
      isPresented: Binding(get: { !error.isEmpty }, set: { if !$0 { error = "" } })
    ) {
      Button("OK") { error = "" }
    } message: {
      Text(error)
    }
    .task(id: phase) {
      guard phase == .active else { return }
      while !Task.isCancelled {
        await store.sync()
        do { try await Task.sleep(for: .seconds(10)) } catch { return }
      }
    }
  }

  @ToolbarContentBuilder private var actions: some ToolbarContent {
    #if os(iOS)
      if #available(iOS 27.1, *) {
        ToolbarItem(placement: .topBarTrailing) { syncButton }.axisBehavior(.verticalPreferred)
          .visibilityPriority(.high)
        ToolbarItem(placement: .bottomBar) { newButton }.axisBehavior(.verticalPreferred)
          .visibilityPriority(.high)
      } else {
        ToolbarItem(placement: .topBarTrailing) { syncButton }
        ToolbarItem(placement: .bottomBar) { newButton }
      }
    #else
      ToolbarItemGroup(placement: .primaryAction) {
        syncButton
        newButton
      }
    #endif
  }

  private var syncButton: some View {
    Button {
      Task { await store.sync() }
    } label: {
      Label("Sync", systemImage: "arrow.triangle.2.circlepath")
    }
  }
  private var newButton: some View {
    Button {
      editor = .new
    } label: {
      Label("New todo", systemImage: "plus")
    }
    .keyboardShortcut("n")
  }

  @ViewBuilder private var conflicts: some View {
    ForEach(store.state.conflicts.keys.sorted(), id: \.self) { id in
      VStack(alignment: .leading) {
        Text(
          "Conflict: " + (store.state.queue.last(where: { $0.todo.id == id })?.todo.title ?? "Todo")
        )
        if let row = store.state.rows[id] {
          Text(row.deleted ? "Deleted on server" : "Server: " + row.title)
        }
        Button("Use server version") { perform { try store.acceptServer(id) } }
      }
    }
  }

  private func group(_ name: String, items: [Todo]) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(name).font(.headline).accessibilityAddTraits(.isHeader)
      ForEach(items) { item in
        HStack(alignment: .center, spacing: 0) {
          Button {
            var row = item
            row.done.toggle()
            perform { try store.save(row) }
          } label: {
            Image(systemName: item.done ? "checkmark.circle.fill" : "circle").frame(
              width: 44, height: 44)
          }.accessibilityLabel((item.done ? "Mark incomplete: " : "Complete: ") + item.title)
          Button {
            editor = .edit(item)
          } label: {
            Text(item.title).strikethrough(item.done).multilineTextAlignment(.leading)
              .fixedSize(horizontal: false, vertical: true)
              .frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 44)
              .contentShape(Rectangle())
          }
          Menu {
            Button("Edit") { editor = .edit(item) }
            Button("Delete", role: .destructive) {
              var row = item
              row.deleted = true
              perform { try store.save(row) }
            }
          } label: {
            Image(systemName: "ellipsis").frame(width: 44, height: 44)
          }
          .accessibilityLabel("Actions for " + item.title)
        }.buttonStyle(.plain)
        Divider()
      }
    }.frame(maxWidth: .infinity, alignment: .leading)
  }

  private func perform(_ action: () throws -> Void) {
    do {
      try action()
      Task { await store.sync() }
    } catch { self.error = error.localizedDescription }
  }
}

extension View {
  @ViewBuilder fileprivate func preferTodoToolbar() -> some View {
    #if os(iOS)
      if #available(iOS 27.1, *) {
        toolbarVerticalCompressionBehavior(.prefersToolbarItems)
      } else {
        self
      }
    #else
      self
    #endif
  }
}

private struct TodoEditor: View {
  @Environment(\.dismiss) private var dismiss
  @FocusState private var focused: Bool
  let selection: Editor
  let save: (String) -> Void
  @State private var title: String

  init(selection: Editor, save: @escaping (String) -> Void) {
    self.selection = selection
    self.save = save
    _title = State(initialValue: selection.title)
  }

  var body: some View {
    NavigationStack {
      Form { TextField("Title", text: $title, axis: .vertical).focused($focused) }
        .formStyle(.grouped)
        .navigationTitle(selection.id == "new" ? "New todo" : "Edit todo")
        #if os(iOS)
          .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
          ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
          ToolbarItem(placement: .confirmationAction) {
            Button("Save") { save(title) }.disabled(
              title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          }
        }
    }
    .onAppear { focused = true }
    #if os(macOS)
      .frame(minWidth: 320, minHeight: 160)
    #endif
  }
}
