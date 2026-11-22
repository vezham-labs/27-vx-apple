// Generated from vx.nav.yaml. Do not edit.
import Foundation

struct AppleNavigationRoute: Identifiable, Hashable {
  let key: String
  let title: String
  let href: String
  let icon: String
  var id: String { key }
}

enum GeneratedNavigation {
  static let routes: [AppleNavigationRoute] = [
    AppleNavigationRoute(key: "home", title: "Home", href: "/", icon: "vx:home"),
    AppleNavigationRoute(key: "academics", title: "Academics", href: "/academics", icon: "vx:book-open"),
    AppleNavigationRoute(key: "students", title: "Students", href: "/students", icon: "vx:users"),
    AppleNavigationRoute(key: "attendance", title: "Attendance", href: "/attendance", icon: "vx:calendar-check"),
    AppleNavigationRoute(key: "fees", title: "Fees", href: "/fees", icon: "vx:receipt")
  ]
}
