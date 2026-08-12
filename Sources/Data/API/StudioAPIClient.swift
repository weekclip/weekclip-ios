import Foundation
import WeekclipShared

/// Studio API client using URLSession
public class StudioAPIClient {
  private let baseURL: URL
  private let session: URLSession
  private var accessToken: String?

  public init(
    baseURL: URL = URL(string: "https://dev-service-api.weekclip.com/api/v1")!,
    accessToken: String? = nil
  ) {
    self.baseURL = baseURL
    self.accessToken = accessToken

    let config = URLSessionConfiguration.default
    config.waitsForConnectivity = true
    config.timeoutIntervalForRequest = 30
    config.timeoutIntervalForResource = 300
    self.session = URLSession(configuration: config)
  }

  /// Update access token for authenticated requests
  public func setAccessToken(_ token: String?) {
    self.accessToken = token
  }

  // MARK: - Studio API

  /// Fetch list of studios for current user
  public func fetchStudios(limit: Int = 10, offset: Int = 0) async throws -> [Studio] {
    var components = URLComponents(url: baseURL.appendingPathComponent("studios"), resolvingAgainstBaseURL: false)!
    components.queryItems = [
      URLQueryItem(name: "limit", value: "\(limit)"),
      URLQueryItem(name: "offset", value: "\(offset)"),
    ]

    guard let url = components.url else {
      throw WeekclipError.invalidURL("studios")
    }

    let (data, response) = try await performRequest(url: url)
    try validateResponse(response)

    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase

    do {
      let listResponse = try decoder.decode(StudioListResponse.self, from: data)
      return listResponse.studios.map { mapStudioResponseToDomain($0) }
    } catch {
      AppLogger.error("Failed to decode studios response", error: error)
      throw WeekclipError.decodingError(error.localizedDescription)
    }
  }

  /// Search studios by name
  public func searchStudios(query: String, limit: Int = 10) async throws -> [Studio] {
    var components = URLComponents(url: baseURL.appendingPathComponent("studios/search"), resolvingAgainstBaseURL: false)!
    components.queryItems = [
      URLQueryItem(name: "q", value: query),
      URLQueryItem(name: "limit", value: "\(limit)"),
    ]

    guard let url = components.url else {
      throw WeekclipError.invalidURL("studios/search")
    }

    let (data, response) = try await performRequest(url: url)
    try validateResponse(response)

    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase

    do {
      let listResponse = try decoder.decode(StudioListResponse.self, from: data)
      return listResponse.studios.map { mapStudioResponseToDomain($0) }
    } catch {
      throw WeekclipError.decodingError(error.localizedDescription)
    }
  }

  // MARK: - Media API

  /// Fetch paginated media list for a studio
  /// - Parameters:
  ///   - studioId: ID of the studio
  ///   - limit: Number of items to fetch (default: 20)
  ///   - lastId: Cursor for pagination - fetch items after this ID
  public func fetchMedia(
    studioId: String,
    limit: Int = 20,
    lastId: String? = nil
  ) async throws -> [StudioMedia] {
    var components = URLComponents(
      url: baseURL.appendingPathComponent("studios/\(studioId)/media"),
      resolvingAgainstBaseURL: false
    )!

    var queryItems = [
      URLQueryItem(name: "limit", value: "\(limit)"),
    ]

    if let lastId = lastId {
      queryItems.append(URLQueryItem(name: "cursor", value: lastId))
    }

    components.queryItems = queryItems

    guard let url = components.url else {
      throw WeekclipError.invalidURL("studios/\(studioId)/media")
    }

    let (data, response) = try await performRequest(url: url)
    try validateResponse(response)

    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase

    do {
      let listResponse = try decoder.decode(MediaListResponse.self, from: data)
      return listResponse.media.map { mapMediaResponseToDomain($0) }
    } catch {
      throw WeekclipError.decodingError(error.localizedDescription)
    }
  }

  // MARK: - Private Helpers

  private func performRequest(url: URL) async throws -> (Data, URLResponse) {
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue("application/json", forHTTPHeaderField: "Accept")

    // Add authorization header if token is available
    if let accessToken = accessToken {
      request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    }

    do {
      let (data, response) = try await session.data(for: request)
      return (data, response)
    } catch {
      AppLogger.error("Network request failed", error: error)
      throw WeekclipError.networkError(error.localizedDescription)
    }
  }

  private func validateResponse(_ response: URLResponse) throws {
    guard let httpResponse = response as? HTTPURLResponse else {
      throw WeekclipError.serverError(statusCode: 0, message: "Invalid response type")
    }

    switch httpResponse.statusCode {
    case 200...299:
      break
    case 401:
      throw WeekclipError.unauthorized
    case 404:
      throw WeekclipError.notFound
    case 507:
      throw WeekclipError.insufficientCapacity
    default:
      let message = HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
      throw WeekclipError.serverError(statusCode: httpResponse.statusCode, message: message)
    }
  }

  // MARK: - Domain Mapping

  private func mapStudioResponseToDomain(_ response: StudioResponse) -> Studio {
    let role = StudioRole(rawValue: response.role) ?? .viewer
    return Studio(
      id: response.id,
      name: response.name,
      description: response.description,
      logoUrl: response.logoUrl,
      role: role,
      mediaCount: response.mediaCount ?? 0,
      createdAt: response.createdAt,
      updatedAt: response.updatedAt
    )
  }

  private func mapMediaResponseToDomain(_ response: MediaResponse) -> StudioMedia {
    let status = MediaStatus(rawValue: response.status) ?? .processing
    let preview = MediaPreview(
      status: response.preview?.status ?? "Missing",
      manifestUrl: response.preview?.manifestUrl
    )
    return StudioMedia(
      id: response.id,
      title: response.title,
      description: response.description,
      studioId: response.studioId,
      thumbnailUrl: response.thumbnailUrl,
      duration: response.duration,
      status: status,
      fileSize: response.fileSize,
      createdAt: response.createdAt,
      updatedAt: response.updatedAt,
      preview: preview
    )
  }
}
