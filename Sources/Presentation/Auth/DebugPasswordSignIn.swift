#if DEBUG
import Foundation
import WeekclipData
import WeekclipShared

/// A password grant behind a button on the login screen — **debug builds only**.
///
/// weekclip's product login is Google and nothing else (weekclip-web
/// `LoginPage.tsx`). This is not a second product login sneaking in; it is the
/// way to put a genuine Supabase token in front of the session code without a
/// Google round trip, which matters for two reasons that outlive 148.5c-b:
///
/// - the OAuth redirect needs `cc.sunglint.weekclip://auth-callback` in the
///   Supabase project's allow list, which is console work this repo cannot do;
/// - even once it is there, a flow that hands control to a browser sheet is a
///   poor thing to hang every device check on.
///
/// The whole file is inside `#if DEBUG`, so the release binary contains neither
/// the endpoint, nor the request, nor the word `password` in a grant — the same
/// intent the Android side gets from a `src/debug/` source set.
///
/// The dev Supabase project has the email provider enabled — `/auth/v1/settings`
/// reports `"email": true` (checked 2026-08-15) — which is what makes this
/// possible at all. Production is a different project and this code is not in
/// the build that talks to it.
///
/// ### It used to run itself, and no longer does
///
/// Until this task it was `DebugAutoSignIn`, called from `AppContainer.start()`
/// at launch, with a documented "only if nothing is stored" check to prove
/// persistence worked. Both properties survive the move and one improves:
///
/// | | before | now |
/// |---|---|---|
/// | when | launch, always | only while the login screen is showing |
/// | "nothing stored" check | an `if` inside this type | structural — the login screen is unreachable with a session |
/// | the gate | walked past | exercised on every debug launch |
///
/// A development build that never sees the gate is a gate nobody is testing.
struct DebugPasswordSignIn: DebugSignInAction {
  let label = "Sign in with a password (debug)"

  private let sessionManager: SessionManager
  private let config: AuthConfig
  private let email: String
  private let password: String
  private let session: URLSession
  private let now: @Sendable () -> Int

  /// - Returns: nil when the build carries no credentials, so the login screen
  ///   shows no button at all rather than one that cannot work.
  static func makeIfConfigured(
    sessionManager: SessionManager,
    config: AuthConfig,
    session: URLSession = APIClient.defaultSession(),
    now: @escaping @Sendable () -> Int = { Int(Date().timeIntervalSince1970) }
  ) -> DebugPasswordSignIn? {
    let email = infoValue("WeekclipDebugSignInEmail")
    let password = infoValue("WeekclipDebugSignInPassword")
    guard !email.isEmpty, !password.isEmpty else {
      AppLog.session.info("no debug credentials in the build; the gate has only Google")
      return nil
    }
    return DebugPasswordSignIn(
      sessionManager: sessionManager,
      config: config,
      email: email,
      password: password,
      session: session,
      now: now
    )
  }

  /// Credentials come from the build environment through `Info.plist`, exactly
  /// like the anon key.
  private static func infoValue(_ key: String) -> String {
    (Bundle.main.object(forInfoDictionaryKey: key) as? String) ?? ""
  }

  func signIn() async -> Bool {
    guard config.isConfigured, let base = config.tokenBaseURL else {
      AppLog.session.notice("WEEKCLIP_SUPABASE_ANON_KEY is missing — cannot sign in")
      return false
    }

    AppLog.session.info("signing in as \(email, privacy: .public)")

    guard
      var components = URLComponents(
        url: base.appendingPathComponent("token"),
        resolvingAgainstBaseURL: false
      )
    else { return false }
    components.queryItems = [URLQueryItem(name: "grant_type", value: "password")]
    guard let url = components.url else { return false }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try? JSONEncoder().encode(["email": email, "password": password])

    do {
      let (data, response) = try await session.data(for: request)
      guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        AppLog.session.notice("sign-in rejected with HTTP \(status, privacy: .public)")
        return false
      }

      guard let profile = DebugGrant.session(from: data, now: now()) else {
        AppLog.session.notice("grant response was missing user or expiry")
        return false
      }

      await sessionManager.adopt(profile)
      AppLog.session.info("signed in as \(profile.userID, privacy: .public); session stored")
      return true
    } catch {
      AppLog.session.notice("sign-in call failed: \(String(describing: error), privacy: .public)")
      return false
    }
  }
}

/// A GoTrue grant, decoded here rather than reused from `WeekclipData`.
///
/// `SupabaseTokenResponse` over there is internal, and making it public so a
/// debug-only file could read it would widen a shipped module's API for code
/// that is not in the shipped binary. Twelve lines is the cheaper trade.
private enum DebugGrant {
  private struct Response: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Int?
    let expiresIn: Int?
    let user: User?

    struct User: Decodable { let id: String }

    enum CodingKeys: String, CodingKey {
      case accessToken = "access_token"
      case refreshToken = "refresh_token"
      case expiresAt = "expires_at"
      case expiresIn = "expires_in"
      case user
    }
  }

  static func session(from data: Data, now: Int) -> ProfileSession? {
    guard
      let body = try? JSONDecoder().decode(Response.self, from: data),
      let userID = body.user?.id,
      let expiresAt = body.expiresAt ?? body.expiresIn.map({ now + $0 })
    else { return nil }

    return ProfileSession(
      accessToken: body.accessToken,
      refreshToken: body.refreshToken,
      expiresAtEpochSeconds: expiresAt,
      userID: userID
    )
  }
}
#endif
