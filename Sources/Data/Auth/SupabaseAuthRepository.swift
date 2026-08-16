import Foundation
import WeekclipShared

/// Turning a finished OAuth round trip into a session.
///
/// ### Why this protocol is in `WeekclipData`, not `WeekclipDomain`
///
/// Every other repository protocol lives in Domain and traffics in domain
/// models. This one traffics in a `ProfileSession` — a Supabase grant, which is
/// a persistence artifact and lives here with the store that writes it. Hoisting
/// it into Domain to satisfy the pattern would pull a wire format up a layer,
/// which is the opposite of what the layering is for. The Android twin has the
/// protocol in `domain` only because *its* session type sits in `core`, below
/// both.
///
/// Separate from `SessionRefresher` even though both hit the same GoTrue
/// endpoint, because they answer to different callers: a failed refresh may
/// mean "sign the user out", while a failed exchange means "the sign-in did not
/// take" and there was no session to lose.
public protocol AuthRepository: Sendable {
  /// - Parameters:
  ///   - code: the authorization code the redirect carried.
  ///   - verifier: the PKCE verifier this process generated before opening the
  ///     browser, read back from `SignInFlowStore`.
  /// - Returns: the grant. Storing it is the caller's job — `SessionManager`
  ///   owns that, and this layer deliberately does not reach into it.
  func exchangeAuthCode(code: String, verifier: String) async -> Result<ProfileSession, AppError>
}

/// `AuthRepository` over Supabase GoTrue.
///
/// Builds its own `URLRequest` against its own `URLSession` rather than going
/// through `APIClient`, for the same reason `SupabaseSessionRefresher` next door
/// does: `APIClient` attaches a session credential and renews on 401, and the
/// mechanism that *obtains* a credential must not depend on having one.
///
/// ### 400 is the interesting status
///
/// GoTrue answers **400** for a bad or already-spent authorization code, not
/// 401. Reporting that as `.unauthorized` would be a lie in the one place it
/// matters: the user is not unauthorized, the exchange failed, and the fix is
/// to press the button again — which is exactly what the wireframe's error
/// state offers ("다시 시도").
public struct SupabaseAuthRepository: AuthRepository {
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

  public func exchangeAuthCode(
    code: String,
    verifier: String
  ) async -> Result<ProfileSession, AppError> {
    guard config.isConfigured, let base = config.tokenBaseURL else {
      // Reachable, not hypothetical — a build with no project key compiled in.
      // Better to say so than to fail DNS and call it "offline".
      return .failure(.unexpected(description: "no Supabase project key in this build"))
    }

    guard
      var components = URLComponents(
        url: base.appendingPathComponent("token"),
        resolvingAgainstBaseURL: false
      )
    else {
      return .failure(.unexpected(description: "could not build the token URL"))
    }
    components.queryItems = [URLQueryItem(name: "grant_type", value: "pkce")]
    guard let url = components.url else {
      return .failure(.unexpected(description: "could not build the token URL"))
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    // GoTrue rejects a request with no project key before it looks at the body,
    // so this header is not optional even for an unauthenticated grant.
    request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    // `auth_code`, not the spec's `code`. Read out of `@supabase/auth-js`
    // (`POST /token?grant_type=pkce`); getting it wrong produces a 400 that
    // looks exactly like an expired code.
    request.httpBody = try? JSONEncoder().encode(
      ["auth_code": code, "code_verifier": verifier]
    )

    do {
      let (data, response) = try await session.data(for: request)
      guard let http = response as? HTTPURLResponse else {
        return .failure(.malformedResponse)
      }
      guard (200..<300).contains(http.statusCode) else {
        return .failure(.server(status: http.statusCode, code: nil, message: nil))
      }
      guard
        let body = try? JSONDecoder().decode(SupabaseTokenResponse.self, from: data),
        let profile = toSession(body)
      else {
        AppLog.session.error("code exchange returned 2xx that was not a grant")
        return .failure(.malformedResponse)
      }
      return .success(profile)
    } catch let error as URLError where error.code == .timedOut {
      return .failure(.timeout)
    } catch {
      return .failure(.offline)
    }
  }

  /// Unlike a refresh, an exchange has no previous session to inherit an id
  /// from, so `user.id` is genuinely required here. A grant with no subject is
  /// not a session this app can act on.
  private func toSession(_ body: SupabaseTokenResponse) -> ProfileSession? {
    guard !body.accessToken.isEmpty, !body.refreshToken.isEmpty else { return nil }
    guard let userID = body.user?.id, !userID.isEmpty else { return nil }
    guard let expiresAt = body.expiresAt ?? body.expiresIn.map({ now() + $0 }) else {
      return nil
    }

    return ProfileSession(
      accessToken: body.accessToken,
      refreshToken: body.refreshToken,
      expiresAtEpochSeconds: expiresAt,
      userID: userID
    )
  }
}
