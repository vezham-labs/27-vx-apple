// Generated from vx.nav.yaml. Do not edit.
import Foundation

struct SchoolRoute: Identifiable, Hashable {
  let key: String
  let title: String
  let href: String
  let icon: String
  var id: String { key }
}

enum GeneratedNavigation {
  static let routes: [SchoolRoute] = [
    SchoolRoute(key: "home", title: "Home", href: "/", icon: "vx:home"),
    SchoolRoute(key: "academics", title: "Academics", href: "/academics", icon: "vx:book-open"),
    SchoolRoute(key: "students", title: "Students", href: "/students", icon: "vx:users"),
    SchoolRoute(key: "attendance", title: "Attendance", href: "/attendance", icon: "vx:calendar-check"),
    SchoolRoute(key: "fees", title: "Fees", href: "/fees", icon: "vx:receipt")
  ]
}
