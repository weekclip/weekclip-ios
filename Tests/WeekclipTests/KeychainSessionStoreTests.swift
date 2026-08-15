import XCTest

@testable import WeekclipData

/// The store against the **real** Keychain.
///
/// This is the test the Android side cannot have. Its unit tests run on a JVM
/// with no `AndroidKeyStore`, so its crypto sits behind a `SecretCipher` seam
/// and only the storage logic is covered off-device. Here the test bundle is
/// hosted by the app on a simulator (`project.yml`: `TEST_HOST`), so
/// `SecItemAdd`/`SecItemCopyMatching` are the ones that actually run — the same
/// calls the shipped app makes, with the same accessibility attribute.
///
/// Each test uses its own service name and deletes it afterwards, so a failure
/// cannot leave state behind that makes the next run pass for the wrong reason.
final class KeychainSessionStoreTests: XCTestCase {
  private var service = ""
  private var store = KeychainSessionStore()

  override func setUp() async throws {
    try await super.setUp()
    service = "cc.sunglint.weekclip.tests.\(UUID().uuidString)"
    store = KeychainSessionStore(service: service)
  }

  override func tearDown() async throws {
    await store.clear()
    try await super.tearDown()
  }

  private func session(
    accessToken: String = "access-1",
    userID: String = "user-1"
  ) -> ProfileSession {
    ProfileSession(
      accessToken: accessToken,
      refreshToken: "refresh-1",
      expiresAtEpochSeconds: 4_242,
      userID: userID
    )
  }

  func testAWrittenSessionComesBackIdentical() async {
    let written = session()

    await store.write(written)

    let read = await store.read()
    XCTAssertEqual(read, written)
  }

  func testNothingStoredReadsAsNoSession() async {
    let read = await store.read()
    XCTAssertNil(read)
  }

  func testWritingTwiceReplacesRatherThanDuplicates() async {
    // `SecItemAdd` on an existing item returns errSecDuplicateItem and stores
    // nothing. If write did not delete first, the second token would be
    // silently dropped and the app would keep using an expired one.
    await store.write(session(accessToken: "first"))
    await store.write(session(accessToken: "second"))

    let read = await store.read()
    XCTAssertEqual(read?.accessToken, "second")
  }

  func testClearRemovesTheStoredSession() async {
    await store.write(session())

    await store.clear()

    let read = await store.read()
    XCTAssertNil(read)
  }

  func testClearingTwiceIsNotAnError() async {
    // errSecItemNotFound is the expected answer the second time, and it must
    // not be logged as a failure or turned into one.
    await store.clear()
    await store.clear()

    let read = await store.read()
    XCTAssertNil(read)
  }

  func testStoredBytesThatAreNotASessionAreDiscardedRatherThanFailedOnForever() async {
    // A shape change or a partial write. Leaving the bytes would mean failing
    // the same decode on every launch, and only a successful write would ever
    // clear it.
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: "profile",
      kSecValueData as String: Data("not a session".utf8),
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
    XCTAssertEqual(SecItemAdd(query as CFDictionary, nil), errSecSuccess)

    let read = await store.read()

    XCTAssertNil(read)
    var probe: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: "profile",
    ]
    probe[kSecReturnData as String] = true
    var item: CFTypeRef?
    XCTAssertEqual(
      SecItemCopyMatching(probe as CFDictionary, &item),
      errSecItemNotFound,
      "an undecodable item must not be left behind"
    )
  }

  func testTheItemIsStoredWithTheAccessibilityBackgroundUploadsNeed() async {
    // PRD-0008 D8: a background URLSession can be woken while the phone is
    // locked in a pocket. A `WhenUnlocked` item is unreadable at that moment,
    // so the upload would resume and be told 401 by a server that has no idea
    // the user is still there.
    await store.write(session())

    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: "profile",
      kSecReturnAttributes as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    XCTAssertEqual(SecItemCopyMatching(query as CFDictionary, &item), errSecSuccess)

    let attributes = item as? [String: Any]
    XCTAssertEqual(
      attributes?[kSecAttrAccessible as String] as? String,
      kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
    )
  }
}
