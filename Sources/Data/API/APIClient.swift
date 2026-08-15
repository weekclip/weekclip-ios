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
  private let tokenProvider: any SessionTokenProvider
  private let decoder: JSONDecoder

  public init(
    baseURL: URL,
    session: URLSession = .shared,
    tokenProvider: any SessionTokenProvider = NoSessionTokenProvider()
  ) {
    self.baseURL = baseURL
    self.session = session
    self.tokenProvider = tokenProvider
    self.decoder = JSONDecoder()
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

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue("application/json", forHTTPHeaderField: "Accept")

    // Omitted rather than sent as "Bearer null" when there is no session: a
    // malformed credential comes back 400, which would hide "not logged in"
    // behind "bad request".
    if let token = tokenProvider.currentAccessToken(), !token.isEmpty {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    do {
      let (data, response) = try await session.data(for: request)
      guard let http = response as? HTTPURLResponse else {
        return .failure(.malformedResponse)
      }

      guard (200..<300).contains(http.statusCode) else {
        return .failure(Self.error(status: http.statusCode, body: data, decoder: decoder))
      }

      do {
        let envelope = try decoder.decode(APIEnvelope<T>.self, from: data)
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
    } catch let urlError as URLError {
      return .failure(Self.error(from: urlError))
    } catch {
      return .failure(.unexpected(description: String(describing: error)))
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
