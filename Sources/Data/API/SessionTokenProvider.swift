import Foundation

/// Supplies the bearer token for API calls, or nil when there is no session.
///
/// A seam, not an implementation. PRD-0008 D6 makes token storage one of the
/// three app-support cores (task 148.5), and D5 adds a second axis on top of it
/// — a non-logged-in guest holds a *share session*, not a profile session, so
/// whatever lands here has to answer "which session is this request on".
///
/// Keychain is the destination (ADR-0002), not `UserDefaults`.
///
/// Until then `NoSessionTokenProvider` is wired. Requests go out
/// unauthenticated and come back 401, which surfaces as `AppError.unauthorized`
/// — the honest result for an app with no login yet, and one the UI renders.
public protocol SessionTokenProvider: Sendable {
  func currentAccessToken() -> String?
}

/// The Phase-2 binding: there is no session, and the code says so.
public struct NoSessionTokenProvider: SessionTokenProvider {
  public init() {}
  public func currentAccessToken() -> String? { nil }
}
