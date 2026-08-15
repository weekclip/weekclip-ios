import Foundation
import WeekclipShared

/// The HTTP client. `URLSession` directly — no wrapper (ADR-0002 D4).
///
/// The reason is not minimalism. PRD-0008 D8 requires uploads that survive
/// backgrounding, and on iOS that means a background `URLSessionConfiguration`
/// driven through delegate callbacks with file-backed bodies. A request wrapper
/// cannot express that, so the most important path in the app would end up
/// bypassing it — leaving two networking styles in one codebase. Better to have
/// one, and have it be the one that can do the hard thing.
///
/// This is also the single place transport failures become `AppError`, so there
/// is exactly one answer to "what does a timeout look like to the UI".
public final class APIClient: Sendable {
  private let baseURL: URL
  private let session: URLSession
  private let credentials: any SessionCredentialProvider
  private let decoder: JSONDecoder

  public init(
    baseURL: URL,
    session: URLSession = APIClient.defaultSession(),
    credentials: any SessionCredentialProvider = NoSessionCredentialProvider()
  ) {
    self.baseURL = baseURL
    self.session = session
    self.credentials = credentials
    self.decoder = JSONDecoder()
  }

  /// The session ordinary API calls use.
  ///
  /// Not `URLSession.shared`, whose `timeoutIntervalForRequest` is **60
  /// seconds**. A minute of spinner on a phone that has drifted off Wi-Fi is
  /// not a loading state, it is a hang — and it is long enough that a UI test
  /// waiting on the spinner to clear times out before the request does, which
  /// reads as an app failure rather than a slow network.
  ///
  /// 15/30 matches the OkHttp client in weekclip-android. Uploads do not use
  /// this session: PRD-0008 D8 needs a background configuration with its own
  /// (much longer) budget.
  public static func defaultSession() -> URLSession {
    let configuration = URLSessionConfiguration.default
    configuration.timeoutIntervalForRequest = 15
    configuration.timeoutIntervalForResource = 30
    return URLSession(configuration: configuration)
  }

  /// GETs `path`, unwraps the envelope, and folds everything that can go wrong
  /// into `AppError`.
  ///
  /// - Parameters:
  ///   - path: relative, without a leading slash (`"studios"`).
  ///   - type: the payload the envelope's `data` key is expected to hold.
  /// - Returns: the decoded payload, or the `AppError` the failure maps to.
  ///   Never throws — the closed error set is the whole point.
  func get<T: Decodable & Sendable>(_ path: String, as type: T.Type) async -> Result<T, AppError> {
    guard let url = URL(string: path, relativeTo: baseURL.appendingTrailingSlash()) else {
      return .failure(.unexpected(description: "could not build a URL for \(path)"))
    }

    // The full path, not the relative one: `SessionAxis` matches on
    // `/api/v1/share/…`, and `path` here is just `share/tok/media`.
    let fullPath = url.path
    let credential = await credentials.credential(for: fullPath)

    switch await send(url: url, credential: credential) {
    case .failure(let error):
      return .failure(error)

    case .success(let first) where first.status == 401 || first.status == 403:
      // Renew and replay once. This is the half of session handling that clock
      // arithmetic cannot cover: a token revoked server-side, or a device whose
      // clock is simply wrong, looks valid right up until the server disagrees.
      let renewed = await credentials.credentialAfterUnauthorized(
        for: fullPath,
        failedCredential: credential
      )

      // Retrying with the identical credential is a guaranteed second 401 —
      // reachable, because the manager hands back the stored token unchanged
      // when another request refreshed first.
      guard let renewed, renewed != credential else {
        return .failure(Self.error(status: first.status, body: first.body, decoder: decoder))
      }

      switch await send(url: url, credential: renewed) {
      case .failure(let error):
        return .failure(error)
      case .success(let second):
        return decode(second, path: path, as: T.self)
      }

    case .success(let first):
      return decode(first, path: path, as: T.self)
    }
  }

  private struct RawResponse: Sendable {
    let status: Int
    let body: Data
  }

  private func send(url: URL, credential: String?) async -> Result<RawResponse, AppError> {
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue("application/json", forHTTPHeaderField: "Accept")

    // Omitted rather than sent as "Bearer null" when there is no session: a
    // malformed credential comes back 400, which would hide "not logged in"
    // behind "bad request".
    if let credential, !credential.isEmpty {
      request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")
    }

    do {
      let (data, response) = try await session.data(for: request)
      guard let http = response as? HTTPURLResponse else {
        return .failure(.malformedResponse)
      }
      return .success(RawResponse(status: http.statusCode, body: data))
    } catch let urlError as URLError {
      return .failure(Self.error(from: urlError))
    } catch {
      return .failure(.unexpected(description: String(describing: error)))
    }
  }

  private func decode<T: Decodable & Sendable>(
    _ response: RawResponse,
    path: String,
    as type: T.Type
  ) -> Result<T, AppError> {
    guard (200..<300).contains(response.status) else {
      return .failure(Self.error(status: response.status, body: response.body, decoder: decoder))
    }

    do {
      let envelope = try decoder.decode(APIEnvelope<T>.self, from: response.body)
      guard let payload = envelope.data else {
        // 2xx with no `data` is not "empty" — an empty list still arrives as
        // {"data":{"items":[]}}. A missing envelope means the response was
        // not what this endpoint promises.
        AppLog.network.error("2xx with no data envelope for \(path, privacy: .public)")
        return .failure(.malformedResponse)
      }
      return .success(payload)
    } catch {
      AppLog.network.error("decode failed for \(path, privacy: .public): \(error)")
      return .failure(.malformedResponse)
    }
  }

  /// `URLError` -> `AppError`.
  static func error(from urlError: URLError) -> AppError {
    switch urlError.code {
    case .timedOut:
      return .timeout
    case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost,
      .cannotConnectToHost, .dnsLookupFailed, .internationalRoamingOff,
      .dataNotAllowed:
      return .offline
    default:
      return .unexpected(description: "URLError \(urlError.code.rawValue)")
    }
  }

  /// Status code + error envelope -> `AppError`.
  static func error(status: Int, body: Data, decoder: JSONDecoder) -> AppError {
    switch status {
    case 401, 403:
      return .unauthorized
    case 404:
      return .notFound
    default:
      // `Empty` rather than `Never`: the failure envelope has no `data` key at
      // all, and a decodable placeholder lets the same type read both shapes.
      let decoded = try? decoder.decode(APIEnvelope<Empty>.self, from: body)
      return .server(
        status: status,
        code: decoded?.error?.code,
        message: decoded?.error?.message
      )
    }
  }
}

/// Stands in for the absent `data` payload of an error response.
struct Empty: Decodable, Sendable {}

extension URL {
  /// `URL(string:relativeTo:)` drops the last path component when the base has
  /// no trailing slash: `.../api/v1` + `studios` resolves to `.../api/studios`.
  /// Same trap as Retrofit's `baseUrl` on the Android side.
  fileprivate func appendingTrailingSlash() -> URL {
    absoluteString.hasSuffix("/") ? self : URL(string: absoluteString + "/") ?? self
  }
}
