import Foundation

/// Exchanges a refresh token for a fresh grant.
///
/// A port, so `SessionManager` can be tested without a socket and so the
/// identity provider stays one implementation away.
public protocol SessionRefresher: Sendable {
  func refresh(_ session: ProfileSession) async -> RefreshOutcome
}

/// Three outcomes, not two.
///
/// The distinction between `rejected` and `unavailable` is the whole point. A
/// refresh that fails because the phone is in a lift must **not** sign the user
/// out — they would come out of the lift to a login screen with nothing to log
/// in with. Only the provider explicitly refusing the refresh token means the
/// session is actually gone.
///
/// weekclip-web reached the same conclusion independently and encodes it in
/// `backendSession.ts`: `api-failure` (network, 5xx) leaves the session alone,
/// `backend-rejected` (401/403) signs out. Two clients disagreeing about when a
/// user is logged out is a support ticket nobody can reproduce.
public enum RefreshOutcome: Equatable, Sendable {
  case refreshed(ProfileSession)

  /// The provider refused the refresh token. It will never work again.
  case rejected

  /// Transient — no network, a timeout, a 5xx, a body we could not read.
  case unavailable
}
