import Foundation
import Alamofire

/// Main API client for WeekClip service
public class WeekclipAPIClient {
  private let baseURL: URL
  private let session: Session

  public init(
    baseURL: URL = URL(string: "https://dev-service-api.weekclip.com/api/v1")!
  ) {
    self.baseURL = baseURL

    let configuration = URLSessionConfiguration.af.default
    configuration.requestCachePolicy = .useProtocolCachePolicy
    configuration.httpMaximumConnectionsPerHost = 4

    self.session = Session(configuration: configuration)
  }

  /// Make a GET request
  public func get<T: Decodable>(
    _ path: String,
    parameters: [String: Any]? = nil
  ) async throws -> T {
    let url = baseURL.appendingPathComponent(path)

    return try await session.request(
      url,
      method: .get,
      parameters: parameters
    )
    .serializingDecodable(T.self)
    .value
  }

  /// Make a POST request
  public func post<T: Decodable, U: Encodable>(
    _ path: String,
    body: U
  ) async throws -> T {
    let url = baseURL.appendingPathComponent(path)

    return try await session.request(
      url,
      method: .post,
      parameters: body,
      encoder: JSONParameterEncoder.default
    )
    .serializingDecodable(T.self)
    .value
  }

  /// Upload file to presigned URL
  public func uploadFile(
    to url: URL,
    data: Data,
    contentType: String
  ) async throws {
    var request = URLRequest(url: url)
    request.httpMethod = "PUT"
    request.setValue(contentType, forHTTPHeaderField: "Content-Type")

    let (_, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse,
          (200..<300).contains(httpResponse.statusCode) else {
      throw WeekclipError.serverError(statusCode: 0, message: "Upload failed")
    }
  }
}

// Import needed for APIClient
import WeekclipShared

/// Error type for API operations
enum APIError: LocalizedError {
  case invalidResponse
  case decodingFailed
  case networkFailed(Error)

  var errorDescription: String? {
    switch self {
    case .invalidResponse:
      return "Invalid API response"
    case .decodingFailed:
      return "Failed to decode API response"
    case .networkFailed(let error):
      return "Network error: \(error.localizedDescription)"
    }
  }
}
