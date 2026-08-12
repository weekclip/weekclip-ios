import Foundation
import Logging

/// Centralized logger for the app using Swift's native Logging package
public enum AppLogger {
  private static let logger = Logger(label: "com.weekclip.ios")

  public static func debug(_ message: String, metadata: [String: Logger.MetadataValue]? = nil) {
    var logger = Self.logger
    logger[metadataKey: "level"] = "debug"
    logger.debug(.init(stringLiteral: message), metadata: metadata)
  }

  public static func info(_ message: String, metadata: [String: Logger.MetadataValue]? = nil) {
    var logger = Self.logger
    logger[metadataKey: "level"] = "info"
    logger.info(.init(stringLiteral: message), metadata: metadata)
  }

  public static func warning(_ message: String, metadata: [String: Logger.MetadataValue]? = nil) {
    var logger = Self.logger
    logger[metadataKey: "level"] = "warning"
    logger.warning(.init(stringLiteral: message), metadata: metadata)
  }

  public static func error(_ message: String, error: Error? = nil, metadata: [String: Logger.MetadataValue]? = nil) {
    var logger = Self.logger
    logger[metadataKey: "level"] = "error"
    if let error = error {
      logger.error(.init(stringLiteral: "\(message): \(error.localizedDescription)"), metadata: metadata)
    } else {
      logger.error(.init(stringLiteral: message), metadata: metadata)
    }
  }
}
