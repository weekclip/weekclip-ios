import Foundation

/// Persistence for the profile session. Survives process death; does not
/// survive uninstall or a wiped keychain item.
///
/// Reads return `nil` for "nothing stored" **and** for "stored but no longer
/// readable". The caller cannot act differently on those two, and an
/// implementation that threw on the second would turn a recoverable sign-out
/// into a crash loop on launch.
///
/// ### Why there is no cipher behind this, unlike Android
///
/// The Android side needs an `AndroidKeystoreCipher` because the platform has
/// no credential store — its recommended path is "generate a key in the
/// Keystore and encrypt the bytes yourself". iOS *has* the store: Keychain
/// items are encrypted by the system, tied to this app, and unreadable by
/// anything else. Adding an encryption layer of our own on top would be
/// ceremony, not defence.
public protocol SessionStore: Sendable {
  func read() async -> ProfileSession?
  func write(_ session: ProfileSession) async
  func clear() async
}
