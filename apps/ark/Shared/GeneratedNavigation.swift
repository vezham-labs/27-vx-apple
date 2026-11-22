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
    AppleNavigationRoute(key: "settings", title: "Settings", href: "/settings", icon: "gearshape")
  ]
}
