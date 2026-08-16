import SwiftUI
import WeekclipDomain
import WeekclipShared

/// The app shell.
///
/// Two gates wrap everything, in this order:
///
/// 1. **version** — is this binary still allowed to talk to the server (D6①)
/// 2. **auth** — is there a profile, or is this a guest with a share link (D4)
///
/// The order is not arbitrary. A version gate that needed a session could not
/// gate the login screen, and an app too old to run may also be too old to sign
/// in — 148.5a states this as the reason `GET /app/version` takes no credential.
///
/// Behind both, a single `NavigationStack` driven by a `[WeekclipRoute]` path,
/// which is what makes a deep link a one-liner: append the parsed route and the
/// stack restores the whole hierarchy.
public struct RootView: View {
  @State private var gate: AppGateState = .checking
  @State private var auth: AuthGateModel

  private let container: AppContainer

  public init(container: AppContainer) {
    self.container = container
    _auth = State(initialValue: container.makeAuthGateModel())
  }

  public var body: some View {
    // `checking` renders nothing: starting at `allowed` would flash the app for
    // a frame before a block landed, and starting at blocked would flash a
    // force-update screen at everyone.
    switch gate {
    case .checking:
      Color.clear.task { await runGate() }
    case .updateRequired(let storeURL):
      UpdateRequiredView(storeURL: storeURL)
    case .allowed:
      gated
    }
  }

  @ViewBuilder
  private var gated: some View {
    Group {
      switch auth.state {
      // Same reasoning as `checking` above, one gate down.
      case .unknown:
        Color.clear

      case .signedOut:
        LoginView(viewModel: container.makeLoginViewModel())
          // Identity, not decoration. Without it SwiftUI reuses the `LoginView`
          // — and its `@State` view model — across a sign-out/sign-in cycle,
          // so the second visit starts holding the first one's error.
          .id("login")

      case .guest(let route):
        GuestHost(route: route, onLeave: auth.leaveGuest)

      case .signedIn:
        signedInHost
      }
    }
    // Universal Links land here. A URL this app does not own returns nil from
    // WeekclipRoute and is ignored rather than guessed at — PRD-0008 D4 keeps
    // public pages on the web.
    //
    // On the shell rather than on one screen, because a link can arrive in any
    // of the four states above and the gate is what decides what it means.
    .onOpenURL { url in
      guard let route = WeekclipRoute(url: url) else {
        AppLog.navigation.notice("ignoring unhandled URL \(url.path, privacy: .public)")
        return
      }
      auth.handle(link: route)
    }
    // Follows the session for the life of the app — including sign-outs this
    // view never asked for, such as a refresh token GoTrue rejects.
    .task { await auth.observe() }
  }

  private var signedInHost: some View {
    NavigationStackHost(container: container, auth: auth)
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
}

/// The signed-in app.
///
/// Its own view so the navigation path is `@State` scoped to being signed in:
/// signing out tears it down, and a stack left over from the previous account
/// cannot be restored under the next one.
private struct NavigationStackHost: View {
  @State private var path: [WeekclipRoute] = []

  let container: AppContainer
  let auth: AuthGateModel

  var body: some View {
    NavigationStack(path: $path) {
      DashboardView(
        viewModel: container.makeDashboardViewModel(),
        onSelect: { studio in path.append(.studio(id: studio.id)) }
      )
      .navigationDestination(for: WeekclipRoute.self) { route in
        PlaceholderScreen(route: route)
      }
    }
    // The deep link is pushed after the stack exists rather than replacing its
    // root, so backing out of a link lands on the dashboard instead of closing
    // the app.
    .onChange(of: auth.pendingRoute) { _, route in
      guard let route else { return }
      path.append(route)
      auth.didNavigate()
    }
    .task {
      // Covers the cold-start case the `onChange` above cannot: the route was
      // already set before this view existed, so there is no change to observe.
      if let route = auth.pendingRoute {
        path.append(route)
        auth.didNavigate()
      }
    }
  }
}

/// The guest surface: one screen, no dashboard behind it.
///
/// Deliberately not a `NavigationStack` with a different root. A guest has
/// nowhere else to go — every other route needs a profile — and a navigation
/// graph whose other entries are all unreachable is an invitation to wire one of
/// them up by accident.
///
/// Leaving hands control back to the gate, which puts the login screen up. The
/// alternative would leave someone who opened a shared album no way to reach the
/// account they may already have.
private struct GuestHost: View {
  let route: WeekclipRoute
  let onLeave: () -> Void

  var body: some View {
    // Phase 5 replaces this with the real share viewer (PRD-0008). What is real
    // today is the gate around it: this renders with no session at all.
    // No identifier on this VStack: SwiftUI would push it down over
    // `screen-title` and `guest-sign-in` both. See the note in `LoginView`.
    VStack(spacing: 12) {
      PlaceholderScreen(route: route)
      Button("Sign in") { onLeave() }
        .accessibilityIdentifier("guest-sign-in")
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
