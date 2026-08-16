import Foundation
import Testing

@testable import WeekclipData

/// The derivation, against the spec's own numbers.
///
/// The first test is RFC 7636 Appendix B verbatim. That matters more than it
/// looks: every other test here could pass while the hash, the encoding and the
/// charset were all wrong together, because this type is the only thing that
/// produces *and* consumes them — a self-consistent mistake is invisible from
/// the inside. Appendix B is the outside.
@Suite("PkceChallenge")
struct PkceChallengeTests {

  @Test("derives the challenge from RFC 7636 Appendix B")
  func appendixB() {
    let challenge = PkceChallenge(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")

    #expect(challenge.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
  }

  @Test("the method string is the lowercase one supabase-js sends")
  func methodCasing() {
    // Not cosmetic — GoTrue stores what /authorize was given and compares at
    // exchange time, so the wrong casing fails only after the user has already
    // finished with Google.
    #expect(PkceChallenge.method == "s256")
  }

  @Test("a generated verifier is base64url and within the legal length")
  func verifierShape() {
    let verifier = PkceChallenge.generate().verifier

    // RFC 7636 §4.1: 43..128 characters from the unreserved set.
    #expect((43...128).contains(verifier.count))
    #expect(verifier.range(of: "[^A-Za-z0-9_-]", options: .regularExpression) == nil)
  }

  @Test("two sign-ins do not share a verifier")
  func verifiersDiffer() {
    // A reused verifier would let a code from one round trip be redeemed by
    // another. Cheap to assert, and the failure it guards against — someone
    // caching the challenge "for performance" — is entirely plausible.
    #expect(PkceChallenge.generate().verifier != PkceChallenge.generate().verifier)
  }

  @Test("the same verifier always derives the same challenge")
  func deterministic() {
    let fixed: (Int) -> Data = { count in Data((0..<count).map { UInt8($0 % 256) }) }

    #expect(
      PkceChallenge.generate(randomBytes: fixed) == PkceChallenge.generate(randomBytes: fixed))
  }
}
