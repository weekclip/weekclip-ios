import SwiftUI
import WeekclipDomain
import WeekclipShared

/// The app shell.
///
/// A single `NavigationStack` driven by a `[WeekclipRoute]` path, which is what
/// makes a deep link a one-liner: append the parsed route and the stack
/// restores the whole hierarchy. Dashboard is a real screen — the vertical
/// slice that proves the spine (composition root -> use case -> repository ->
/// `URLSession` -> the live `GET /studios` contract) is connected end to end.
/// Everything else is still a placeholder and lands in Phase 5 (PRD-0008).
public struct RootView: View {
  @State private var path: [WeekclipRoute] = []

  private let container: AppContainer

  public init(container: AppContainer) {
    self.container = container
  }

  public var body: some View {
    NavigationStack(path: $path) {
      DashboardView(
        viewModel: container.makeDashboardViewModel(),
        onSelect: { studio in path.append(.studio(id: studio.id)) }
      )
      .navigationDestination(for: WeekclipRoute.self) { route in
        PlaceholderScreen(route: route)
      }
    }
    // Universal Links land here. A URL this app does not own returns nil from
    // WeekclipRoute and is ignored rather than guessed at — PRD-0008 D4 keeps
    // public pages on the web.
    .onOpenURL { url in
      guard let route = WeekclipRoute(url: url) else {
        AppLog.navigation.notice("ignoring unhandled URL \(url.path, privacy: .public)")
        return
      }
      path.append(route)
    }
  }
}

/// Stands in for every destination Phase 5 has not built yet.
///
/// Tagged so `maestro/` can assert which screen is showing without depending on
/// its copy.
struct PlaceholderScreen: View {
  let route: WeekclipRoute

  var body: some View {
    VStack(spacing: 8) {
      Text(title)
        .font(.title2)
        .accessibilityIdentifier("screen-title")
      Text("Not implemented yet")
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var title: String {
    switch route {
    case .dashboard: return "Dashboard"
    case .studio: return "Studio"
    case .media: return "Media"
    case .members: return "Members"
    case .capacity: return "Capacity"
    case .invite: return "Invite"
    case .share: return "Share"
    }
  }
}
