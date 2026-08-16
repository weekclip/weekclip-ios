import Foundation

/// The two things a sign-in in progress must not lose.
///
/// - the **PKCE verifier**, without which the authorization code cannot be
///   exchanged. Losing it turns a completed Google prompt into "log in again".
/// - the **intended route**, the deep link that sent the user to the login
///   screen. Losing it drops them on the dashboard having forgotten what they
///   tapped — the wireframe's "돌아갈 곳을 잃었다"
///   (`screens/auth/mobile.html`, state `denied`).
///
/// ### Why on disk
///
/// The route needs it outright: a link can arrive, the user can put the phone
/// down at the login screen, and iOS can reclaim the app.
///
/// The verifier's case is weaker here than on Android, and saying so is worth
/// more than pretending the platforms are the same. `ASWebAuthenticationSession`
/// presents **over** this app rather than switching to a browser, so weekclip
/// stays foreground for the whole round trip and is close to the last thing iOS
/// would reclaim; the Android twin genuinely does get killed behind a Custom
/// Tab. It is stored anyway because one mechanism for both values is simpler
/// than two, and a `UserDefaults` write costs nothing next to a network round
/// trip.
///
/// ### Both are read once and deleted
///
/// `take`, not `get`. A verifier is single-use by construction: after the
/// exchange it authenticates nothing, and leaving it only widens the window in
/// which it is worth stealing. An intended route that survived its own
/// navigation would re-fire on the next unrelated sign-in.
///
/// ### `UserDefaults`, not the Keychain
///
/// `KeychainSessionStore` holds the session because a refresh token is a
/// long-lived credential. Neither value here is: the verifier is a nonce that
/// is worthless the moment it is used or abandoned, and a route is not a
/// secret. Both are gone from disk within one round trip either way.
///
/// Mirrors `core/auth/SignInFlowStore.kt` in weekclip-android.
///
/// `@unchecked Sendable` because `UserDefaults` is not annotated `Sendable`
/// even though Apple documents it as thread-safe ("UserDefaults is thread-safe",
/// *Preferences and Settings Programming Guide*). The alternative — holding the
/// suite name and calling `UserDefaults(suiteName:)` on every access — trades a
/// documented guarantee for an allocation per read and an optional to unwrap.
public struct SignInFlowStore: @unchecked Sendable {
  private let defaults: UserDefaults

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  public func putVerifier(_ verifier: String) {
    defaults.set(verifier, forKey: Keys.verifier)
  }

  public func takeVerifier() -> String? {
    take(Keys.verifier)
  }

  /// - Parameter route: a parsed route, never a raw URL.
  public func putIntendedRoute(_ route: WeekclipRouteRef) {
    defaults.set(route.path, forKey: Keys.intendedRoute)
  }

  public func takeIntendedRoute() -> String? {
    take(Keys.intendedRoute)
  }

  /// Whether a route is waiting, without consuming it.
  ///
  /// The login screen shows a "you will be taken back to what you opened" line
  /// off this, and it has to still be there for the navigation that follows the
  /// exchange.
  public var hasIntendedRoute: Bool {
    defaults.string(forKey: Keys.intendedRoute) != nil
  }

  /// Abandons a sign-in in progress. Called on sign-out and on a refusal.
  public func clear() {
    defaults.removeObject(forKey: Keys.verifier)
    defaults.removeObject(forKey: Keys.intendedRoute)
  }

  private func take(_ key: String) -> String? {
    guard let value = defaults.string(forKey: key) else { return nil }
    defaults.removeObject(forKey: key)
    return value
  }

  private enum Keys {
    static let verifier = "signIn.pkceVerifier.v1"
    static let intendedRoute = "signIn.intendedRoute.v1"
  }
}

/// The shape this store needs from a route, without depending on the type.
///
/// `WeekclipRoute` lives in `WeekclipPresentation`, which sits **above** this
/// module — so importing it here would invert the dependency graph. A protocol
/// with the one property that is actually stored keeps the arrow pointing the
/// right way, and the store still cannot be handed an unparsed URL by mistake.
public protocol WeekclipRouteRef: Sendable {
  var path: String { get }
}
