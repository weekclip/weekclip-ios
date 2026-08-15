#if DEBUG
import Foundation
import WeekclipShared

/// Puts a real session in front of the app on a debug build, so that "the
/// session store works" can be checked by looking at the screen instead of only
/// at a test report.
///
/// weekclip's product login is Google OAuth and nothing else (weekclip-web
/// `LoginPage.tsx`). This is not a second product login sneaking in; it is the
/// only way to get a genuine token in front of the session code before the
/// OAuth clients exist (148.5c-b). The whole file is inside `#if DEBUG`, so the
/// release binary contains neither the endpoint nor the request — the same
/// intent the Android side gets from a `src/debug/` source set.
///
/// The dev Supabase project has the email provider enabled —
/// `/auth/v1/settings` reports `"email": true` (checked 2026-08-15) — which is
/// what makes this possible at all. Production is a different project and this
/// code is not in the build that talks to it.
///
/// ### It signs in **only if there is nothing stored**
///
/// That order is the interesting part, not an optimisation. On first launch the
/// log says `signed in`; on every launch after, `restored`, and the dashboard
/// fills without a single call to Supabase. A build that signed in every time
/// would render the same screen whether or not persistence worked at all —
/// which is the failure mode 148.3d warned about: a check that cannot fail is
/// not a check.
public struct DebugAutoSignIn: Sendable {
  private let sessionManager: SessionManager
  private let config: AuthConfig
  private let session: URLSession
  private let now: @Sendable () -> Int

  public init(
    sessionManager: SessionManager,
    config: AuthConfig,
    session: URLSession = APIClient.defaultSession(),
    now: @escaping @Sendable () -> Int = { Int(Date().timeIntervalSince1970) }
  ) {
    self.sessionManager = sessionManager
    self.config = config
    self.session = session
    self.now = now
  }

  /// Credentials come from the build environment through `Info.plist`, exactly
  /// like the anon key. Absent means inert: the app then behaves like a release
  /// build — no session, `AppError.unauthorized`, error screen.
  private static func infoValue(_ key: String) -> String {
    (Bundle.main.object(forInfoDictionaryKey: key) as? String) ?? ""
  }

  public func run() async {
    let email = Self.infoValue("WeekclipDebugSignInEmail")
    let password = Self.infoValue("WeekclipDebugSignInPassword")

    guard !email.isEmpty, !password.isEmpty else {
      AppLog.session.info("no debug credentials in the build; staying signed out")
      return
    }
    guard config.isConfigured, let base = config.tokenBaseURL else {
      AppLog.session.notice("WEEKCLIP_SUPABASE_ANON_KEY is missing — cannot sign in")
      return
    }

    if case .signedIn(let userID) = await sessionManager.reload() {
      AppLog.session.info(
        "restored a stored session for \(userID, privacy: .public) — no network needed")
      return
    }
    AppLog.session.info("nothing stored; signing in as \(email, privacy: .public)")

    guard
      var components = URLComponents(
        url: base.appendingPathComponent("token"),
        resolvingAgainstBaseURL: false
      )
    else { return }
    components.queryItems = [URLQueryItem(name: "grant_type", value: "password")]
    guard let url = components.url else { return }

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
        return
      }

      let body = try JSONDecoder().decode(SupabaseTokenResponse.self, from: data)
      guard
        let userID = body.user?.id,
        let expiresAt = body.expiresAt ?? body.expiresIn.map({ now() + $0 })
      else {
        AppLog.session.notice("grant response was missing user or expiry")
        return
      }

      await sessionManager.adopt(
        ProfileSession(
          accessToken: body.accessToken,
          refreshToken: body.refreshToken,
          expiresAtEpochSeconds: expiresAt,
          userID: userID
        )
      )
      AppLog.session.info("signed in as \(userID, privacy: .public); session stored")
    } catch {
      AppLog.session.notice("sign-in call failed: \(String(describing: error), privacy: .public)")
    }
  }
}
#endif
