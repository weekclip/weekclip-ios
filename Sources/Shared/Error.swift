import Foundation

/// Error types for the WeekClip app
public enum WeekclipError: LocalizedError {
  case networkError(String)
  case decodingError(String)
  case invalidURL(String)
  case serverError(statusCode: Int, message: String)
  case unauthorized
  case notFound
  case insufficientCapacity
  case unknown(Error)

  public var errorDescription: String? {
    switch self {
    case .networkError(let message):
      return "Network Error: \(message)"
    case .decodingError(let message):
      return "Decoding Error: \(message)"
    case .invalidURL(let url):
      return "Invalid URL: \(url)"
    case .serverError(let statusCode, let message):
      return "Server Error (\(statusCode)): \(message)"
    case .unauthorized:
      return "Unauthorized - please log in"
    case .notFound:
      return "Resource not found"
    case .insufficientCapacity:
      return "Insufficient storage capacity"
    case .unknown(let error):
      return error.localizedDescription
    }
  }

  public var recoverySuggestion: String? {
    switch self {
    case .networkError:
      return "Check your internet connection and try again"
    case .decodingError:
      return "The app data format is invalid. Please try updating."
    case .invalidURL:
      return "The URL is invalid. Please contact support."
    case .serverError:
      return "Please try again later or contact support"
    case .unauthorized:
      return "Please log in again"
    case .notFound:
      return "The resource you're looking for no longer exists"
    case .insufficientCapacity:
      return "Please upgrade your plan or delete some content"
    case .unknown:
      return "An unexpected error occurred. Please try again."
    }
  }
}
