import Foundation
import Testing
import WeekclipDomain
import WeekclipShared

@testable import WeekclipData

/// The repository against real response bytes.
///
/// A stub of `StudioRepository` would skip the layer most likely to be wrong —
/// the envelope. weekclip-api nests list payloads twice (`data.items`) and puts
/// `traceId` in different places on success and failure; only decoding actual
/// JSON can catch a mistake there.
///
/// The JSON below is copied from the shape `presentStudioMembership` emits
/// (weekclip-api `src/studios/application/present-studio-membership.ts`). If the
/// server changes it, this is where that should hurt.
@Suite("RemoteStudioRepository")
struct StudioRepositoryContractTests {

  private func makeRepository(
    status: Int,
    body: String,
    onRequest: (@Sendable (URLRequest) -> Void)? = nil
  ) -> RemoteStudioRepository {
    StubURLProtocol.set(status: status, body: Data(body.utf8), onRequest: onRequest)

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]

    return RemoteStudioRepository(
      client: APIClient(
        baseURL: URL(string: "https://service-api.weekclip.test/api/v1")!,
        session: URLSession(configuration: configuration)
      )
    )
  }

  @Test("decodes the nested data.items envelope into domain studios")
  func decodesTheEnvelope() async {
    let repository = makeRepository(
      status: 200,
      body: """
        {
          "data": {
            "items": [
              {
                "id": "st_1",
                "slug": "family",
                "name": "Family",
                "ownerId": "pr_1",
                "createdAt": "2026-08-01T00:00:00.000Z",
                "updatedAt": "2026-08-10T00:00:00.000Z",
                "role": "Owner"
              }
            ]
          },
          "meta": { "traceId": "trace-1" }
        }
        """
    )

    let result = await repository.getStudios()

    let studios = try? result.get()
    #expect(studios?.count == 1)
    #expect(studios?.first?.id == "st_1")
    #expect(studios?.first?.name == "Family")
    // The wire sends "Owner" capitalised; the domain must not carry wire casing.
    #expect(studios?.first?.role == .owner)
  }

  @Test("the request goes to /api/v1/studios, not /api/studios")
  func buildsTheRightPath() async {
    let recorded = RequestRecorder()
    let repository = makeRepository(
      status: 200,
      body: #"{"data":{"items":[]},"meta":{"traceId":"t"}}"#,
      onRequest: { recorded.store($0.url?.path) }
    )

    _ = await repository.getStudios()

    // URL(string:relativeTo:) drops the last path component when the base has
    // no trailing slash. That failure is silent — the request succeeds against
    // the wrong path — so it gets its own assertion.
    #expect(recorded.value == "/api/v1/studios")
  }

  @Test("an empty items array is a success, not an error")
  func emptyIsSuccess() async {
    let repository = makeRepository(
      status: 200, body: #"{"data":{"items":[]},"meta":{"traceId":"t"}}"#)

    let result = await repository.getStudios()

    #expect((try? result.get())?.isEmpty == true)
  }

  @Test("a 2xx with no data envelope is malformed, not empty")
  func missingDataIsMalformed() async {
    let repository = makeRepository(status: 200, body: #"{"meta":{"traceId":"t"}}"#)

    let result = await repository.getStudios()

    #expect(result.failure == .malformedResponse)
  }

  @Test("401 and 403 both fold into unauthorized", arguments: [401, 403])
  func authFailures(status: Int) async {
    let repository = makeRepository(
      status: status,
      body: #"{"error":{"code":"unauthorized","message":"no session"},"traceId":"t"}"#
    )

    #expect(await repository.getStudios().failure == .unauthorized)
  }

  @Test("404 becomes notFound")
  func notFound() async {
    let repository = makeRepository(
      status: 404,
      body: #"{"error":{"code":"not_found","message":"gone"},"traceId":"t"}"#
    )

    #expect(await repository.getStudios().failure == .notFound)
  }

  @Test("a 500 keeps the server's own error code so logs can be correlated")
  func serverErrorKeepsCode() async {
    let repository = makeRepository(
      status: 500,
      body: #"{"error":{"code":"internal","message":"boom"},"traceId":"t"}"#
    )

    #expect(
      await repository.getStudios().failure
        == .server(status: 500, code: "internal", message: "boom")
    )
  }

  @Test("a 500 with an unparseable body still reports the status")
  func serverErrorWithHTMLBody() async {
    let repository = makeRepository(status: 500, body: "<html>gateway blew up</html>")

    #expect(
      await repository.getStudios().failure == .server(status: 500, code: nil, message: nil)
    )
  }

  @Test("unknown roles degrade to .unknown instead of failing the whole list")
  func unknownRoleDegrades() async {
    let repository = makeRepository(
      status: 200,
      body: #"{"data":{"items":[{"id":"st_9","role":"Archivist"}]},"meta":{"traceId":"t"}}"#
    )

    let studios = try? await repository.getStudios().get()

    #expect(studios?.first?.role == .unknown)
  }
}

// MARK: - Helpers

extension Result {
  /// The error, or nil. Reads better than a `switch` in every assertion.
  var failure: Failure? {
    if case .failure(let error) = self { return error }
    return nil
  }
}

/// Captures a value from the `URLProtocol`'s thread for the test to read.
private final class RequestRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var stored: String?

  func store(_ value: String?) {
    lock.withLock { stored = value }
  }

  var value: String? {
    lock.withLock { stored }
  }
}

/// Serves a canned response without opening a socket.
///
/// `URLProtocol` rather than a mock `URLSession`: `URLSession` is not a
/// protocol, and subclassing it to intercept is unsupported. This is the seam
/// Apple actually provides, and it exercises the real request pipeline —
/// headers, status handling, and all — up to the byte level.
private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
  private struct Stub {
    let status: Int
    let body: Data
    let onRequest: (@Sendable (URLRequest) -> Void)?
  }

  nonisolated(unsafe) private static var stub: Stub?
  private static let lock = NSLock()

  static func set(status: Int, body: Data, onRequest: (@Sendable (URLRequest) -> Void)?) {
    lock.withLock { stub = Stub(status: status, body: body, onRequest: onRequest) }
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let stub = Self.lock.withLock { Self.stub }
    stub?.onRequest?(request)

    let response = HTTPURLResponse(
      url: request.url!,
      statusCode: stub?.status ?? 200,
      httpVersion: "HTTP/1.1",
      headerFields: ["Content-Type": "application/json"]
    )!

    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: stub?.body ?? Data())
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}
