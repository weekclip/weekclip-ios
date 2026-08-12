import Foundation

/// Keychain storage for sensitive data like tokens
public class KeychainStorage {
  private let service = "com.weekclip.ios"

  public static let shared = KeychainStorage()

  // MARK: - Access Token

  public func saveAccessToken(_ token: String) throws {
    try save(token, for: "access_token")
  }

  public func getAccessToken() -> String? {
    try? retrieve("access_token")
  }

  public func deleteAccessToken() throws {
    try delete("access_token")
  }

  // MARK: - Refresh Token

  public func saveRefreshToken(_ token: String) throws {
    try save(token, for: "refresh_token")
  }

  public func getRefreshToken() -> String? {
    try? retrieve("refresh_token")
  }

  public func deleteRefreshToken() throws {
    try delete("refresh_token")
  }

  // MARK: - Generic Methods

  private func save(_ value: String, for key: String) throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
      kSecValueData as String: value.data(using: .utf8) ?? Data(),
    ]

    // Try to delete existing value first
    SecItemDelete(query as CFDictionary)

    // Add new value
    let status = SecItemAdd(query as CFDictionary, nil)
    guard status == errSecSuccess else {
      throw KeychainError.saveFailed(status)
    }
  }

  private func retrieve(_ key: String) throws -> String {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
      kSecReturnData as String: true,
    ]

    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)

    guard status == errSecSuccess else {
      throw KeychainError.retrieveFailed(status)
    }

    guard let data = result as? Data,
          let value = String(data: data, encoding: .utf8) else {
      throw KeychainError.decodingFailed
    }

    return value
  }

  private func delete(_ key: String) throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
    ]

    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw KeychainError.deleteFailed(status)
    }
  }

  public func deleteAll() throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
    ]

    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw KeychainError.deleteFailed(status)
    }
  }
}

// MARK: - Errors

enum KeychainError: LocalizedError {
  case saveFailed(OSStatus)
  case retrieveFailed(OSStatus)
  case decodingFailed
  case deleteFailed(OSStatus)

  var errorDescription: String? {
    switch self {
    case .saveFailed(let status):
      return "Failed to save to Keychain (status: \(status))"
    case .retrieveFailed(let status):
      return "Failed to retrieve from Keychain (status: \(status))"
    case .decodingFailed:
      return "Failed to decode value from Keychain"
    case .deleteFailed(let status):
      return "Failed to delete from Keychain (status: \(status))"
    }
  }
}
