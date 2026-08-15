import Foundation
import Security
import WeekclipShared

/// The session in the Keychain, as one JSON blob under a generic-password item.
///
/// ### `kSecAttrAccessibleAfterFirstUnlock`, not `WhenUnlocked`
///
/// This is the decision in this file. PRD-0008 D8 requires uploads that keep
/// running while the app is in the background, and on iOS that means a
/// background `URLSession` whose delegate can be woken **while the phone is in
/// a pocket, locked**. A `WhenUnlocked` item is unreadable at that moment, so
/// the upload would resume, fail to attach a token, and be told 401 by a server
/// that has no idea the user is still there.
///
/// `AfterFirstUnlock` is the weaker of the two — the item is readable any time
/// after the first unlock following a boot — and it is the one that matches
/// what the app actually has to do. `ThisDeviceOnly` is added so the item is
/// never carried to a new phone by an encrypted backup: a session belongs to a
/// device, and a restored-from-backup token is one nobody signed in for.
///
/// ### One item, replaced wholesale
///
/// `SecItemUpdate` after a failed `SecItemAdd` is the usual dance; deleting and
/// re-adding is one code path instead of two and cannot leave a half-updated
/// item. The window where nothing is stored is inside a single actor-isolated
/// call.
public struct KeychainSessionStore: SessionStore {
  private let service: String
  private let account: String

  /// - Parameters:
  ///   - service: overridable so tests can use a unique keychain item and clean
  ///     up after themselves, rather than fighting over the app's.
  ///   - account: the item's account attribute; one profile session per app.
  public init(
    service: String = "cc.sunglint.weekclip.session",
    account: String = "profile"
  ) {
    self.service = service
    self.account = account
  }

  public func read() async -> ProfileSession? {
    var query = baseQuery()
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)

    guard status == errSecSuccess, let data = item as? Data else {
      if status != errSecItemNotFound {
        AppLog.session.error("keychain read failed with OSStatus \(status, privacy: .public)")
      }
      return nil
    }

    guard let session = try? JSONDecoder().decode(ProfileSession.self, from: data) else {
      // Stored bytes that are not a session — a shape change, a partial write.
      // Leaving them would mean failing the same decode on every launch
      // forever, and only a successful write would ever clear it.
      AppLog.session.error("stored session could not be decoded; discarding it")
      await clear()
      return nil
    }

    return session
  }

  public func write(_ session: ProfileSession) async {
    guard let data = try? JSONEncoder().encode(session) else {
      AppLog.session.error("session could not be encoded; nothing was stored")
      return
    }

    await clear()

    var query = baseQuery()
    query[kSecValueData as String] = data
    query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

    let status = SecItemAdd(query as CFDictionary, nil)
    if status != errSecSuccess {
      AppLog.session.error("keychain write failed with OSStatus \(status, privacy: .public)")
    }
  }

  public func clear() async {
    let status = SecItemDelete(baseQuery() as CFDictionary)
    if status != errSecSuccess && status != errSecItemNotFound {
      AppLog.session.error("keychain delete failed with OSStatus \(status, privacy: .public)")
    }
  }

  private func baseQuery() -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }
}
