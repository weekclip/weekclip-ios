import Foundation
import WeekclipShared

/// A GoTrue grant response, as measured against the dev project on 2026-08-15:
/// `access_token`, `refresh_token`, `token_type`, `expires_in`, `expires_at`,
/// `user`, and (for a password grant) `weak_password`.
///
/// `expires_at` is optional even though the observed response always carried
/// it. The field is not in GoTrue's documented minimum, and a client that fails
/// when an optional field disappears ships a broken build the day the provider
/// trims its payload — `expires_in` is the fallback.
struct SupabaseTokenResponse: Decodable, Sendable {
  let accessToken: String
  let refreshToken: String
  let expiresAt: Int?
  let expiresIn: Int?
  let user: SupabaseUser?

  enum CodingKeys: String, CodingKey {
    case accessToken = "access_token"
    case refreshToken = "refresh_token"
    case expiresAt = "expires_at"
    case expiresIn = "expires_in"
    case user
  }
}

struct SupabaseUser: Decodable, Sendable {
  let id: String
}

/// `SessionRefresher` over Supabase GoTrue.
///
/// It builds its own `URLRequest` against its own `URLSession` rather than
/// going through `APIClient`, and that separation is load-bearing: `APIClient`
/// attaches a session credential and renews on 401. A refresh routed through it
/// would ask for a token in order to get a token, and a refresh that came back
/// 401 would try to fix itself by refreshing. **The mechanism that renews the
/// credential must not depend on the credential.**
///
/// The status mapping is the rest of the file, and it is deliberate:
///
/// | status | outcome | why |
/// |--------|---------|-----|
/// | 2xx with a token | `.refreshed` | |
/// | 400 · 401 · 403 | `.rejected` | GoTrue answers **400** for `refresh_token_not_found`, not 401. Treating only 401 as fatal would leave a dead session retrying forever |
/// | 2xx we cannot read | `.unavailable` | our own parsing failing is not evidence the user's session ended |
/// | anything else, transport failure | `.unavailable` | a lift, a captive portal, a 502 |
public struct SupabaseSessionRefresher: SessionRefresher {
  private let config: AuthConfig
  private let session: URLSession
  private let now: @Sendable () -> Int

  public init(
    config: AuthConfig,
    session: URLSession = APIClient.defaultSession(),
    now: @escaping @Sendable () -> Int = { Int(Date().timeIntervalSince1970) }
  ) {
    self.config = config
    self.session = session
    self.now = now
  }

  public func refresh(_ profile: ProfileSession) async -> RefreshOutcome {
    guard
      let base = config.tokenBaseURL,
      var components = URLComponents(
        url: base.appendingPathComponent("token"),
        resolvingAgainstBaseURL: false
      )
    else {
      return .unavailable
    }

    components.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token")]
    guard let url = components.url else { return .unavailable }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    // GoTrue rejects a request with no project key before it looks at the body,
    // so this header is not optional even for an unauthenticated grant.
    request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.httpBody = try? JSONEncoder().encode(["refresh_token": profile.refreshToken])

    do {
      let (data, response) = try await session.data(for: request)
      guard let http = response as? HTTPURLResponse else { return .unavailable }

      if Self.rejectingStatuses.contains(http.statusCode) {
        return .rejected
      }
      guard (200..<300).contains(http.statusCode) else { return .unavailable }
      guard let body = try? JSONDecoder().decode(SupabaseTokenResponse.self, from: data) else {
        AppLog.session.error("refresh returned 2xx that was not a grant")
        return .unavailable
      }

      guard let renewed = toSession(body, previous: profile) else { return .unavailable }
      return .refreshed(renewed)
    } catch {
      return .unavailable
    }
  }

  private func toSession(
    _ body: SupabaseTokenResponse,
    previous: ProfileSession
  ) -> ProfileSession? {
    guard !body.accessToken.isEmpty, !body.refreshToken.isEmpty else { return nil }

    guard let expiresAt = body.expiresAt ?? body.expiresIn.map({ now() + $0 }) else {
      return nil
    }

    return ProfileSession(
      accessToken: body.accessToken,
      refreshToken: body.refreshToken,
      expiresAtEpochSeconds: expiresAt,
      // A refresh response is not required to re-state the user. Keeping the
      // previous id is right *because* a refresh cannot change identity — the
      // refresh token belongs to one user by construction.
      userID: body.user?.id ?? previous.userID
    )
  }

  private static let rejectingStatuses: Set<Int> = [400, 401, 403]
}
