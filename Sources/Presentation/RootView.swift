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
  @State private var gate: AppGateState = .checking

  private let container: AppContainer

  public init(container: AppContainer) {
    self.container = container
  }

  public var body: some View {
    // The version gate wraps the whole app rather than sitting on one screen
    // (PRD-0008 D6①). `checking` renders nothing: starting at `allowed` would
    // flash the dashboard for a frame before a block landed, and starting at
    // blocked would flash a force-update screen at everyone.
    switch gate {
    case .checking:
      Color.clear.task { await runGate() }
    case .updateRequired(let storeURL):
      UpdateRequiredView(storeURL: storeURL)
    case .allowed:
      content
    }
  }

  /// One check, once, at launch. Absent in the preview/test container, which
  /// never talks to a server — there is nothing to gate against.
  private func runGate() async {
    guard let getAppUpdateRequirement = container.getAppUpdateRequirement else {
      gate = .allowed
      return
    }
    // `CFBundleVersion` rather than `CFBundleShortVersionString`: the server
    // compares build numbers precisely because integer comparison cannot be got
    // subtly wrong the way semver can.
    let build =
      Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
    switch await getAppUpdateRequirement(currentBuild: build) {
    case .notRequired:
      gate = .allowed
    case .required(let storeURL):
      gate = .updateRequired(storeURL: storeURL)
    }
  }

  private var content: some View {
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
    // Process-start work. Empty in a release build; on debug it restores or
    // mints the session (148.5). `.task` rather than `.onAppear` so it is async
    // and cancelled with the view.
    .task { await container.start() }
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
