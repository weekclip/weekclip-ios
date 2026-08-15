import Foundation
import Testing

@testable import WeekclipData

/// The refresher against real GoTrue bytes.
///
/// The success payload is the actual response shape from the dev Supabase
/// project, captured on 2026-08-15 (values replaced). Decoding a hand-written
/// approximation would prove nothing about the field that matters most —
/// `expires_at`, which is what stops the app from asking the device what time
/// it is.
@Suite("SupabaseSessionRefresher", .serialized)
struct SupabaseSessionRefresherTests {

  private let previous = ProfileSession(
    accessToken: "old-access",
    refreshToken: "old-refresh",
    expiresAtEpochSeconds: 900,
    userID: "user-1"
  )

  private func makeRefresher(
    status: Int,
    body: String,
    anonKey: String = "anon-key"
  ) -> SupabaseSessionRefresher {
    QueuedURLProtocol.reset(with: [QueuedURLProtocol.Response(status: status, body: body)])
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [QueuedURLProtocol.self]
    return SupabaseSessionRefresher(
      config: AuthConfig(
        supabaseURL: URL(string: "https://project.supabase.co"),
        anonKey: anonKey
      ),
      session: URLSession(configuration: configuration),
      now: { 1_000 }
    )
  }

  @Test("a grant response becomes a session")
  func grantBecomesSession() async {
    let refresher = makeRefresher(
      status: 200,
      body: """
        {
          "access_token": "new-access",
          "token_type": "bearer",
          "expires_in": 3600,
          "expires_at": 1786787949,
          "refresh_token": "new-refresh",
          "user": { "id": "user-1", "email": "adam@weekclip.com" }
        }
        """
    )

    let outcome = await refresher.refresh(previous)

    #expect(
      outcome
        == .refreshed(
          ProfileSession(
            accessToken: "new-access",
            refreshToken: "new-refresh",
            expiresAtEpochSeconds: 1_786_787_949,
            userID: "user-1"
          )
        )
    )
  }

  @Test("an absent expires_at falls back to expires_in on the device clock")
  func fallsBackToExpiresIn() async {
    let refresher = makeRefresher(
      status: 200,
      body: #"{"access_token":"a","refresh_token":"r","expires_in":3600}"#
    )

    let outcome = await refresher.refresh(previous)

    guard case .refreshed(let session) = outcome else {
      Issue.record("expected a refreshed session, got \(outcome)")
      return
    }
    #expect(session.expiresAtEpochSeconds == 1_000 + 3_600)
  }

  /// A refresh token belongs to exactly one user by construction, so the id
  /// cannot have changed — and dropping it would strand the app in `signedIn`
  /// with nobody signed in.
  @Test("a refresh response without a user keeps the previous identity")
  func keepsPreviousIdentity() async {
    let refresher = makeRefresher(
      status: 200,
      body: #"{"access_token":"a","refresh_token":"r","expires_at":2000}"#
    )

    let outcome = await refresher.refresh(previous)

    guard case .refreshed(let session) = outcome else {
      Issue.record("expected a refreshed session, got \(outcome)")
      return
    }
    #expect(session.userID == "user-1")
  }

  /// GoTrue answers 400 here, not 401. Treating only 401 as fatal would leave a
  /// permanently dead session retrying on every screen forever.
  @Test("400 refresh_token_not_found is a rejection, not a network blip")
  func fourHundredIsRejection() async {
    let refresher = makeRefresher(
      status: 400,
      body: #"{"code":400,"error_code":"refresh_token_not_found","msg":"Invalid Refresh Token"}"#
    )

    #expect(await refresher.refresh(previous) == .rejected)
  }

  @Test("401 and 403 are rejections", arguments: [401, 403])
  func unauthorizedIsRejection(status: Int) async {
    let refresher = makeRefresher(status: status, body: "{}")

    #expect(await refresher.refresh(previous) == .rejected)
  }

  @Test("a 500 is transient and must not sign the user out")
  func serverErrorIsTransient() async {
    let refresher = makeRefresher(status: 500, body: "{}")

    #expect(await refresher.refresh(previous) == .unavailable)
  }

  /// Our own parsing failing is not evidence that the user's session ended.
  @Test("a 200 that carries no token is transient rather than a sign-out")
  func unreadable200IsTransient() async {
    let refresher = makeRefresher(status: 200, body: #"{"unexpected":"shape"}"#)

    #expect(await refresher.refresh(previous) == .unavailable)
  }

  @Test(
    "the request is a refresh_token grant carrying the stored refresh token and the project key")
  func requestShape() async {
    var captured: URLRequest?
    QueuedURLProtocol.reset(with: [QueuedURLProtocol.Response(status: 500, body: "{}")])
    QueuedURLProtocol.onRequest = { captured = $0 }
    defer { QueuedURLProtocol.onRequest = nil }

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [QueuedURLProtocol.self]
    let refresher = SupabaseSessionRefresher(
      config: AuthConfig(
        supabaseURL: URL(string: "https://project.supabase.co"), anonKey: "anon-key"),
      session: URLSession(configuration: configuration),
      now: { 1_000 }
    )

    _ = await refresher.refresh(previous)

    #expect(captured?.httpMethod == "POST")
    #expect(captured?.url?.path == "/auth/v1/token")
    #expect(captured?.url?.query == "grant_type=refresh_token")
    // GoTrue rejects a request with no project key before it looks at the body.
    #expect(captured?.value(forHTTPHeaderField: "apikey") == "anon-key")
  }
}
