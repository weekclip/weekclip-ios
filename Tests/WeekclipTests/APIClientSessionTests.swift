import Foundation
import Testing
import WeekclipShared

@testable import WeekclipData

/// What actually goes out on the wire, and what happens when it comes back 401.
///
/// Asserted from the requests the transport saw, so a test cannot pass because
/// the client built a request nobody sent.
@Suite("APIClient session handling", .serialized)
struct APIClientSessionTests {

  private func makeClient(
    credentials: any SessionCredentialProvider,
    responses: [QueuedURLProtocol.Response]
  ) -> APIClient {
    QueuedURLProtocol.reset(with: responses)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [QueuedURLProtocol.self]
    return APIClient(
      baseURL: URL(string: "https://service-api.weekclip.test/api/v1")!,
      session: URLSession(configuration: configuration),
      credentials: credentials
    )
  }

  private static let ok = QueuedURLProtocol.Response(status: 200, body: #"{"data":{"items":[]}}"#)

  @Test("a profile request carries the profile bearer")
  func profileRequestCarriesBearer() async {
    let client = makeClient(
      credentials: StubCredentialProvider(profile: "token-1"),
      responses: [Self.ok]
    )

    _ = await client.get("studios", as: ItemsPayload<StudioDTO>.self)

    #expect(QueuedURLProtocol.authorizationHeaders() == ["Bearer token-1"])
  }

  /// The failure this prevents is concrete. weekclip-api verifies
  /// `/share/:token/*` with the share link's own HMAC key
  /// (`share-link-session.ts`), not with Supabase's JWKS — so a profile JWT
  /// sent there is rejected, and a signed-in user would be told they cannot
  /// view a link that works fine in a browser.
  @Test("a guest share request does not carry the profile bearer")
  func guestRequestOmitsProfileBearer() async {
    let client = makeClient(
      credentials: StubCredentialProvider(profile: "token-1"),
      responses: [Self.ok]
    )

    _ = await client.get("share/tok/media", as: ItemsPayload<StudioDTO>.self)

    #expect(QueuedURLProtocol.authorizationHeaders() == [nil])
  }

  /// Not `Bearer null`: that is a malformed credential and comes back 400,
  /// which hides "not logged in" behind "bad request".
  @Test("no session means no header at all")
  func noSessionMeansNoHeader() async {
    let client = makeClient(
      credentials: StubCredentialProvider(profile: nil),
      responses: [Self.ok]
    )

    _ = await client.get("studios", as: ItemsPayload<StudioDTO>.self)

    #expect(QueuedURLProtocol.authorizationHeaders() == [nil])
  }

  @Test("a 401 is renewed and the request is replayed once")
  func renewsAndReplays() async {
    let credentials = StubCredentialProvider(profile: "stale", renewed: { _ in "fresh" })
    let client = makeClient(
      credentials: credentials,
      responses: [QueuedURLProtocol.Response(status: 401, body: "{}"), Self.ok]
    )

    let result = await client.get("studios", as: ItemsPayload<StudioDTO>.self)

    #expect(QueuedURLProtocol.authorizationHeaders() == ["Bearer stale", "Bearer fresh"])
    switch result {
    case .success: break
    case .failure(let error): Issue.record("expected success, got \(error)")
    }
  }

  @Test("a 401 that cannot be renewed is surfaced instead of retried")
  func unrenewable401IsSurfaced() async {
    let client = makeClient(
      credentials: StubCredentialProvider(profile: "stale", renewed: { _ in nil }),
      responses: [QueuedURLProtocol.Response(status: 401, body: "{}")]
    )

    let result = await client.get("studios", as: ItemsPayload<StudioDTO>.self)

    #expect(QueuedURLProtocol.requestCount() == 1)
    #expect(result.failure == .unauthorized)
  }

  /// Reachable: when another request refreshed first, the manager hands back
  /// what is stored — which may be the very token that just failed.
  @Test("a renewal that returns the same credential is not replayed")
  func identicalRenewalIsNotReplayed() async {
    let client = makeClient(
      credentials: StubCredentialProvider(profile: "stale", renewed: { $0 }),
      responses: [QueuedURLProtocol.Response(status: 401, body: "{}")]
    )

    let result = await client.get("studios", as: ItemsPayload<StudioDTO>.self)

    #expect(QueuedURLProtocol.requestCount() == 1)
    #expect(result.failure == .unauthorized)
  }

  @Test("a retry that also gets 401 stops rather than looping")
  func retryThatFailsStops() async {
    let client = makeClient(
      credentials: StubCredentialProvider(profile: "stale", renewed: { _ in "fresh" }),
      responses: [
        QueuedURLProtocol.Response(status: 401, body: "{}"),
        QueuedURLProtocol.Response(status: 401, body: "{}"),
      ]
    )

    let result = await client.get("studios", as: ItemsPayload<StudioDTO>.self)

    #expect(QueuedURLProtocol.requestCount() == 2)
    #expect(result.failure == .unauthorized)
  }

  /// A share session cannot be renewed: it is minted by entering the link's
  /// password and expires on its own schedule. Retrying would spend another
  /// round trip to be told the same thing.
  @Test("a 401 on the guest surface is not renewed")
  func guest401IsNotRenewed() async {
    let credentials = StubCredentialProvider(profile: "token", renewed: { _ in "fresh" })
    let client = makeClient(
      credentials: credentials,
      responses: [QueuedURLProtocol.Response(status: 401, body: "{}")]
    )

    _ = await client.get("share/tok/media", as: ItemsPayload<StudioDTO>.self)

    #expect(QueuedURLProtocol.requestCount() == 1)
  }
}

extension Result where Failure == AppError {
  fileprivate var failure: AppError? {
    if case .failure(let error) = self { return error }
    return nil
  }
}

/// Answers per axis, exactly as the real provider does, with the manager
/// replaced by two closures.
private struct StubCredentialProvider: SessionCredentialProvider {
  let profile: String?
  var renewed: (@Sendable (String?) -> String?)?

  init(profile: String?, renewed: (@Sendable (String?) -> String?)? = nil) {
    self.profile = profile
    self.renewed = renewed
  }

  func credential(for path: String) async -> String? {
    SessionAxis.of(path: path) == .profile ? profile : nil
  }

  func credentialAfterUnauthorized(for path: String, failedCredential: String?) async -> String? {
    guard SessionAxis.of(path: path) == .profile else { return nil }
    return renewed?(failedCredential)
  }
}

/// A transport that answers a scripted sequence and remembers what it was
/// asked, so a replay can be told apart from a single call.
final class QueuedURLProtocol: URLProtocol, @unchecked Sendable {
  struct Response: Sendable {
    let status: Int
    let body: String
  }

  nonisolated(unsafe) private static var queue: [Response] = []
  nonisolated(unsafe) private static var seen: [String?] = []
  /// Set by a test that wants the whole request, not just its bearer.
  nonisolated(unsafe) static var onRequest: ((URLRequest) -> Void)?
  private static let lock = NSLock()

  static func reset(with responses: [Response]) {
    lock.withLock {
      queue = responses
      seen = []
    }
  }

  static func authorizationHeaders() -> [String?] {
    lock.withLock { seen }
  }

  static func requestCount() -> Int {
    lock.withLock { seen.count }
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    Self.onRequest?(request)
    let next: Response? = Self.lock.withLock {
      Self.seen.append(request.value(forHTTPHeaderField: "Authorization"))
      return Self.queue.isEmpty ? nil : Self.queue.removeFirst()
    }

    let response = HTTPURLResponse(
      url: request.url!,
      statusCode: next?.status ?? 500,
      httpVersion: "HTTP/1.1",
      headerFields: ["Content-Type": "application/json"]
    )!

    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data((next?.body ?? "{}").utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}
