import CryptoKit
import Foundation

/// A PKCE (RFC 7636) verifier and the challenge derived from it.
///
/// ### Why a public client needs this at all
///
/// The authorization code comes back over `cc.sunglint.weekclip://`, and a
/// private-use URI scheme has **no registry** — RFC 8252 §8.6 says so plainly,
/// and on Android any app may declare the same one. So the code by itself does
/// not identify us. PKCE binds it to a secret this process generated and never
/// put in a URL, and the exchange fails for anyone holding only the code.
///
/// It is also why a native app cannot use the implicit flow the web uses: there
/// the token arrives in a URL fragment that an interceptor would simply read.
///
/// ### `s256`, not `plain`
///
/// `plain` sends the verifier itself as the challenge, which puts it in the
/// outbound URL and defeats the point. GoTrue accepts both; only one is worth
/// having.
///
/// ⚠️ The method string is lowercase **`s256`**, not the `S256` spelled in
/// RFC 7636 §4.3. Not a guess: `@supabase/auth-js`'s
/// `getCodeChallengeAndMethod` returns the literal `'s256'`, and that library
/// already talks to these same Supabase projects from weekclip-web. The mirror
/// of this file is `core/auth/PkceChallenge.kt` in weekclip-android.
public struct PkceChallenge: Equatable, Sendable {
  public let verifier: String
  public let challenge: String

  /// What `code_challenge_method` has to say. See the type note on casing.
  public static let method = "s256"

  /// Derives the challenge for an already-chosen `verifier`.
  public init(verifier: String) {
    self.verifier = verifier
    // US-ASCII per RFC 7636 §4.2. The verifier is base64url, so it has no
    // characters outside ASCII anyway; stating the encoding means a locale
    // cannot change the hash.
    let digest = SHA256.hash(data: Data(verifier.utf8))
    self.challenge = Data(digest).base64URLEncodedString()
  }

  /// 32 bytes of entropy, base64url-encoded to 43 characters — the low end of
  /// RFC 7636 §4.1's 43..128 range, and what every reference implementation
  /// uses.
  ///
  /// `randomBytes` is a parameter so a test can pin the output. Nothing in the
  /// app passes it.
  public static func generate(
    randomBytes: (Int) -> Data = Self.secureRandomBytes
  ) -> PkceChallenge {
    PkceChallenge(verifier: randomBytes(verifierByteCount).base64URLEncodedString())
  }

  private static let verifierByteCount = 32

  /// `SystemRandomNumberGenerator` is documented as cryptographically secure on
  /// Apple platforms — it is `arc4random_buf` underneath. Reaching for
  /// `SecRandomCopyBytes` instead would add an error path that cannot fire.
  public static func secureRandomBytes(_ count: Int) -> Data {
    var generator = SystemRandomNumberGenerator()
    return Data((0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
  }
}

extension Data {
  /// base64url without padding (RFC 4648 §5).
  ///
  /// Foundation has no built-in for this. `=` is not URL-safe in a query
  /// string without further escaping, and RFC 7636 §4.1 excludes it from the
  /// verifier alphabet outright.
  func base64URLEncodedString() -> String {
    base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}
