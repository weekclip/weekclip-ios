import Foundation
import Observation
import WeekclipData
import WeekclipShared

/// Who is allowed past the front door, and where they land.
///
/// PRD-0008 D4 put every product surface behind a profile except one. This is
/// that rule as code:
///
/// | entry | gate |
/// |-------|------|
/// | app icon, or any link under `/dashboard` · `/studios` · `/invite` | sign in first |
/// | a share link (`/share/:token`) | straight through, no account |
///
/// The exception is not a convenience. `SessionAxis` already says a share link
/// carries **its own** credential — an HMAC over the link's key, not a profile
/// JWT — so a guest is not a signed-out user waiting to sign in; they are a
/// different kind of caller the API already knows how to answer. Requiring a
/// profile there would make the app refuse a link a browser opens fine.
///
/// Invites are deliberately on the other side of that line. Accepting one
/// attaches a studio to an account, so there has to be an account first; the web
/// flow reaches the same conclusion (F3, "초대 수락 전 로그인").
///
/// ### `.unknown` renders nothing, on purpose
///
/// Reading the stored session is an `await` into the Keychain. Treating "not
/// loaded yet" as "signed out" flashes a login screen at a user who is signed
/// in — the same failure `SessionState` warns about, and the same shape as the
/// version gate's `.checking`.
///
/// Mirrors `ui/auth/AuthGateViewModel.kt` in weekclip-android.
@MainActor
@Observable
public final class AuthGateModel {
  public private(set) var state: AuthGateState = .unknown

  /// A route the shell should open once it is showing a `NavigationStack`.
  ///
  /// Separate from `state` because it is an instruction, not a condition: the
  /// shell consumes it with `didNavigate()` and it must not fire twice.
  public private(set) var pendingRoute: WeekclipRoute?

  private let sessionManager: SessionManager
  private let flowStore: SignInFlowStore

  /// Held rather than acted on until the session is known. A link can arrive
  /// before the store has been read, and deciding then would send a signed-in
  /// user to the login screen.
  private var unresolvedLink: WeekclipRoute?

  /// Sticky for the life of the guest visit — see `leaveGuest()`.
  private var guestRoute: WeekclipRoute?

  private var sessionState: SessionState = .unknown

  public init(sessionManager: SessionManager, flowStore: SignInFlowStore) {
    self.sessionManager = sessionManager
    self.flowStore = flowStore
  }

  /// Follows the session for the life of the app. Started from the root view's
  /// `.task`, which cancels it when the view goes away — which, for the root,
  /// is never.
  public func observe() async {
    // Kicks the store read, and does it **before** subscribing so the stream's
    // opening value is already the answer. `SessionManager` starts at
    // `.unknown` and leaves it only when something reads the store; nothing
    // else in the app does until a request needs a token, and by then the gate
    // has long since had to decide what to draw. Without this line the gate sits
    // at `.unknown` — a blank screen — forever.
    await sessionManager.reload()

    for await session in await sessionManager.stateStream() {
      sessionState = session
      resolve()
    }
  }

  /// - Parameter route: already parsed by `WeekclipRoute`; never a raw URL.
  public func handle(link route: WeekclipRoute) {
    unresolvedLink = route
    resolve()
  }

  public func didNavigate() {
    pendingRoute = nil
  }

  /// The guest backed out of the shared album.
  ///
  /// They land on the login screen rather than a dashboard, because a guest does
  /// not have one. This is the only way out of `.guest` — a signed-out user has
  /// nothing else in the app to reach.
  public func leaveGuest() {
    guestRoute = nil
    resolve()
  }

  private func resolve() {
    switch sessionState {
    case .unknown:
      state = .unknown

    case .signedIn:
      // A profile outranks a guest visit: the same link opens inside the app
      // proper, where `SessionAxis` picks the right credential per request.
      guestRoute = nil

      let link = unresolvedLink
      unresolvedLink = nil
      // The link that just arrived wins over one parked earlier — it is what
      // the user tapped most recently. The parked one is still consumed so it
      // cannot resurface on a later sign-in.
      let parked = flowStore.takeIntendedRoute().flatMap { WeekclipRoute(path: $0) }
      if let route = link ?? parked {
        pendingRoute = route
      }

      state = .signedIn

    case .signedOut:
      if let link = unresolvedLink {
        unresolvedLink = nil
        if link.isGuestReachable {
          guestRoute = link
        } else {
          // Parked on disk, not in this object: signing in can outlive it.
          flowStore.putIntendedRoute(link)
        }
      }

      state = guestRoute.map(AuthGateState.guest) ?? .signedOut
    }
  }
}

public enum AuthGateState: Equatable, Sendable {
  /// The stored session has not been read yet. Renders nothing.
  case unknown

  /// Show the first gate.
  case signedOut

  /// A share link opened without an account. The route is the only reachable screen.
  case guest(WeekclipRoute)

  /// Show the app.
  case signedIn
}

extension WeekclipRoute {
  /// Whether this route can be opened with no account at all.
  ///
  /// The single exception PRD-0008 D4 carves out of "everything needs a
  /// profile", and it is drawn to match the **API**, not a UI preference:
  /// `SessionAxis` routes the versioned API's `share` subtree to the guest
  /// credential — the share link's own HMAC — and everything else to the
  /// profile JWT. A screen the gate lets through that then calls a profile
  /// endpoint would render a 401, so the two definitions have to agree.
  /// `SessionAxisTests` pins the other half.
  ///
  /// `invite` is deliberately not here. Accepting an invite attaches a studio
  /// to an account, so the account has to exist first — the same conclusion
  /// weekclip-web reaches in flow F3.
  public var isGuestReachable: Bool {
    if case .share = self { return true }
    return false
  }
}

/// Lets `SignInFlowStore` persist a route without `WeekclipData` importing this
/// module, which would invert the dependency graph.
extension WeekclipRoute: WeekclipRouteRef {}
