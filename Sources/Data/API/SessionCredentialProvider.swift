import Foundation

/// Supplies the bearer credential for a request, or nil when there is none for
/// that `SessionAxis`.
///
/// This replaces the Phase-2 `SessionTokenProvider`, whose signature was
/// `currentAccessToken() -> String?` — no request, so no way to answer "which
/// session is this request on", and synchronous, so no way to refresh. Its own
/// doc comment flagged the first gap and named this task; reading the API
/// contract in 148.5 turned it from a foreseeable problem into a demonstrable
/// one (see `SessionAxis`).
///
/// Async by design. The Android side has to bridge a suspend call into a
/// blocking OkHttp interceptor with `runBlocking`; here `URLSession` is already
/// being awaited, so the refresh simply happens in line with no bridge and no
/// thread to block.
public protocol SessionCredentialProvider: Sendable {
  /// - Parameter path: the request's path, e.g. `/api/v1/studios`.
  /// - Returns: the bearer credential for that path's axis, or nil if there is
  ///   no session on it.
  func credential(for path: String) async -> String?

  /// Called only after the server answered 401, with the credential that
  /// failed. Returns a renewed one to retry with, or nil to give up.
  func credentialAfterUnauthorized(for path: String, failedCredential: String?) async -> String?
}

/// The real provider: profile credentials come from `SessionManager`.
///
/// The guest axis returns nil. Nothing stores a share session yet, because no
/// screen mints one. The seam takes the path so that when the share viewer
/// arrives (PRD-0008 D5, task 148.7) it plugs in here without `APIClient` or a
/// single repository changing.
public struct SessionManagerCredentialProvider: SessionCredentialProvider {
  private let sessionManager: SessionManager

  public init(sessionManager: SessionManager) {
    self.sessionManager = sessionManager
  }

  public func credential(for path: String) async -> String? {
    switch SessionAxis.of(path: path) {
    case .profile: return await sessionManager.accessToken()
    case .guest: return nil
    }
  }

  public func credentialAfterUnauthorized(
    for path: String,
    failedCredential: String?
  ) async -> String? {
    switch SessionAxis.of(path: path) {
    case .profile:
      return await sessionManager.accessTokenAfterUnauthorized(failedCredential: failedCredential)
    case .guest:
      // A share session cannot be renewed: it is minted by entering the link's
      // password and expires on its own schedule (`SHARE_LINK_SESSION_TTL_MS`).
      // Retrying is the guest re-entering the password, not a token exchange.
      return nil
    }
  }
}

/// The binding for a client with no session at all — previews, tests that are
/// about something else, and the composition root before sign-in exists.
public struct NoSessionCredentialProvider: SessionCredentialProvider {
  public init() {}
  public func credential(for path: String) async -> String? { nil }
  public func credentialAfterUnauthorized(
    for path: String,
    failedCredential: String?
  ) async -> String? { nil }
}
