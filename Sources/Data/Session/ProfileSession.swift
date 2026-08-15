import Foundation

/// A signed-in profile's Supabase session, exactly as it is persisted.
///
/// "Session" is not an abstraction this app invented: weekclip-api verifies a
/// **Supabase access token** against the project's remote JWKS
/// (`supabase-token-verifier.ts`), so what the app stores has to be the real
/// grant — access token, refresh token, and the absolute expiry it came with.
///
/// Measured against the dev project (2026-08-15): a grant returns
/// `expires_in: 3600` and an absolute `expires_at` in **epoch seconds**. The
/// absolute value is what is kept — `expires_in` is relative to a clock this app
/// does not own, and re-deriving it on every read would make the stored session
/// drift every time the device's clock did.
///
/// This is the *profile* axis. The guest/share axis is a different credential
/// with a different lifecycle — see `SessionAxis`.
public struct ProfileSession: Codable, Equatable, Sendable {
  public let accessToken: String
  public let refreshToken: String
  public let expiresAtEpochSeconds: Int
  public let userID: String

  public init(
    accessToken: String,
    refreshToken: String,
    expiresAtEpochSeconds: Int,
    userID: String
  ) {
    self.accessToken = accessToken
    self.refreshToken = refreshToken
    self.expiresAtEpochSeconds = expiresAtEpochSeconds
    self.userID = userID
  }

  /// 60s against a 3600s token: 1.7% of its life spent avoiding a race.
  public static let refreshSkewSeconds = 60

  /// Whether this token can still be put on a request at `now`.
  ///
  /// The skew is subtracted deliberately. A token with three seconds of life
  /// left is not usable: the request still has to be built, resolve DNS,
  /// complete a TLS handshake and cross a mobile link, and it is validated on
  /// arrival rather than on departure. Refreshing slightly early costs one extra
  /// call an hour; refreshing slightly late costs a 401 on a screen someone is
  /// looking at.
  public func isUsable(at now: Int, skewSeconds: Int = ProfileSession.refreshSkewSeconds) -> Bool {
    now + skewSeconds < expiresAtEpochSeconds
  }
}

/// What the app currently knows about the signed-in profile.
///
/// `unknown` is a real state, not a placeholder: on a cold start the session
/// lives in the Keychain and reading it is an async call. A UI that treats "not
/// loaded yet" as "signed out" shows a login screen to someone who is signed in
/// — the same class of bug as 148.3d, where a refresh with no rows loaded
/// rendered as "No studios yet."
public enum SessionState: Equatable, Sendable {
  case unknown
  case signedOut
  case signedIn(userID: String)
}
