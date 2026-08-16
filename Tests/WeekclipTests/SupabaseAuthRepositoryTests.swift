import Foundation
import Testing
import WeekclipShared

@testable import WeekclipData

/// The PKCE exchange against real GoTrue bytes.
///
/// The layer most likely to be wrong here is the request body's field names —
/// GoTrue wants `auth_code` where OAuth says `code` — so the first test reads
/// the bytes that went out rather than trusting the type that produced them.
@Suite("SupabaseAuthRepository", .serialized)
struct SupabaseAuthRepositoryTests {

  private func makeRepository(
    status: Int,
    body: String,
    anonKey: String = "anon-key"
  ) -> SupabaseAuthRepository {
    QueuedURLProtocol.reset(with: [QueuedURLProtocol.Response(status: status, body: body)])
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [QueuedURLProtocol.self]
    return SupabaseAuthRepository(
      config: AuthConfig(
        supabaseURL: URL(string: "https://project.supabase.co"),
        anonKey: anonKey
      ),
      session: URLSession(configuration: configuration),
      now: { 1_000 }
    )
  }

  /// The dev project's grant shape, captured 2026-08-15 (values replaced).
  /// `expires_at` in epoch seconds is the field that matters most — it is what
  /// stops the app from asking the device what time it is.
  private static let grant = """
    {
      "access_token": "access-token-value",
      "refresh_token": "refresh-token-value",
      "token_type": "bearer",
      "expires_in": 3600,
      "expires_at": 1755300000,
      "user": { "id": "cb19da57-0000-0000-0000-000000000000" }
    }
    """

  @Test("sends the grant type and field names GoTrue expects")
  func requestShape() async throws {
    let repository = makeRepository(status: 200, body: Self.grant)
    nonisolated(unsafe) var sent: URLRequest?
    QueuedURLProtocol.onRequest = { sent = $0 }
    defer { QueuedURLProtocol.onRequest = nil }

    _ = await repository.exchangeAuthCode(code: "code-1", verifier: "verifier-1")

    let request = try #require(sent)
    #expect(
      request.url?.absoluteString == "https://project.supabase.co/auth/v1/token?grant_type=pkce")
    #expect(request.value(forHTTPHeaderField: "apikey") == "anon-key")

    // URLProtocol strips httpBody into httpBodyStream, so read it back out.
    let body = try #require(request.httpBody ?? request.httpBodyStream.map(Self.drain))
    let text = String(decoding: body, as: UTF8.self)
    // `auth_code`, not `code`. Getting this wrong produces a 400 that looks
    // exactly like an expired code.
    #expect(text.contains("\"auth_code\":\"code-1\""))
    #expect(text.contains("\"code_verifier\":\"verifier-1\""))
  }

  @Test("a grant response becomes a session")
  func grantBecomesSession() async throws {
    let repository = makeRepository(status: 200, body: Self.grant)

    let result = await repository.exchangeAuthCode(code: "code-1", verifier: "verifier-1")

    let session = try #require(try result.get())
    #expect(session.accessToken == "access-token-value")
    #expect(session.refreshToken == "refresh-token-value")
    // The absolute expiry the grant carried, not one re-derived from device time.
    #expect(session.expiresAtEpochSeconds == 1_755_300_000)
    #expect(session.userID == "cb19da57-0000-0000-0000-000000000000")
  }

  @Test("a rejected code is a server error, not an expired session")
  func rejectedCode() async {
    let repository = makeRepository(
      status: 400,
      body: #"{"error":"invalid_grant","error_description":"invalid flow state"}"#
    )

    let result = await repository.exchangeAuthCode(code: "code-1", verifier: "verifier-1")

    // GoTrue answers 400 here, not 401. Folding it into `.unauthorized` would
    // tell the user their session ended — they never had one — and would
    // suppress the retry that actually fixes it.
    #expect(result == .failure(.server(status: 400, code: nil, message: nil)))
  }

  @Test("a 200 that is not a grant does not become a half-built session")
  func malformedGrant() async {
    let repository = makeRepository(status: 200, body: #"{"ok":true}"#)

    let result = await repository.exchangeAuthCode(code: "code-1", verifier: "verifier-1")

    #expect(result == .failure(.malformedResponse))
  }

  @Test("a grant with no user is refused")
  func grantWithNoUser() async {
    let repository = makeRepository(
      status: 200,
      body: #"{"access_token":"a","refresh_token":"r","expires_in":3600}"#
    )

    let result = await repository.exchangeAuthCode(code: "code-1", verifier: "verifier-1")

    // Unlike a refresh, an exchange has no previous session to inherit an id
    // from. A session with no subject is not one this app can act on.
    #expect(result == .failure(.malformedResponse))
  }

  @Test("expires_in is used when the response omits expires_at")
  func relativeExpiry() async throws {
    let repository = makeRepository(
      status: 200,
      body: #"{"access_token":"a","refresh_token":"r","expires_in":3600,"user":{"id":"u1"}}"#
    )

    let result = await repository.exchangeAuthCode(code: "code-1", verifier: "verifier-1")

    #expect(try result.get().expiresAtEpochSeconds == 4_600)
  }

  @Test("a build with no project key does not reach the network")
  func unconfigured() async {
    let repository = makeRepository(status: 200, body: Self.grant, anonKey: "")

    let result = await repository.exchangeAuthCode(code: "code-1", verifier: "verifier-1")

    guard case .failure(.unexpected) = result else {
      Issue.record("expected .unexpected, got \(result)")
      return
    }
    #expect(QueuedURLProtocol.requestCount() == 0)
  }

  private static func drain(_ stream: InputStream) -> Data {
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 1024)
    while stream.hasBytesAvailable {
      let read = stream.read(&buffer, maxLength: buffer.count)
      if read <= 0 { break }
      data.append(contentsOf: buffer[0..<read])
    }
    return data
  }
}
