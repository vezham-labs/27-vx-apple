import SwiftUI

private let routes = GeneratedNavigation.routes

struct ContentView: View {
  private let colors: [Color] = [.blue, .teal, .orange, .purple]
  @State private var preferredCompactColumn: NavigationSplitViewColumn = .detail
  var body: some View {
    NavigationSplitView(preferredCompactColumn: $preferredCompactColumn) {
      List {
        ForEach(routes) { route in
          NavigationLink(value: route.href) {
            Label(route.title, systemImage: symbol(route.icon))
          }
        }
      }
      .navigationTitle("School OS")
    } detail: {
      NavigationStack {
        dashboard(for: "/")
          .navigationDestination(for: String.self) { href in
            dashboard(for: href)
          }
      }
    }
  }

  private func dashboard(for href: String) -> some View {
    let title = routes.first(where: { $0.href == href })?.title ?? "Home"
    return ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Text("Good morning").font(.title2).foregroundStyle(.secondary)
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 14)], spacing: 14) {
          ForEach(Array(["Students", "Attendance", "Classes", "Fees"].enumerated()), id: \.offset) { index, label in
            VStack(alignment: .leading, spacing: 12) {
              Image(systemName: symbol(label.lowercased())).font(.title2).foregroundStyle(colors[index])
              Text(label).font(.headline)
              Text(["1,248 students", "92% today", "32 classes", "$42,800 due"][index]).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, minHeight: 105, alignment: .leading).padding()
              .background(.quaternary, in: RoundedRectangle(cornerRadius: 18))
          }
        }
        Text("Today").font(.title2.bold()).padding(.top, 8)
        Label("09:00 · Morning assembly", systemImage: "clock")
        Label("10:30 · Grade 8 mathematics", systemImage: "book")
        Label("12:00 · Attendance review", systemImage: "checkmark.circle")
      }.padding().frame(maxWidth: 900, alignment: .leading)
    }.navigationTitle(title)
  }

  private func symbol(_ icon: String) -> String {
    switch icon {
    case "vx:home": "house"
    case "vx:book-open": "book"
    case "vx:users": "person.3"
    case "vx:calendar-check": "calendar"
    case "vx:receipt": "creditcard"
    case "students": "person.3"
    case "attendance": "calendar"
    case "classes": "book"
    case "fees": "creditcard"
    default: "square.grid.2x2"
    }
  }
}
