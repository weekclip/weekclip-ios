import Foundation
import Testing

@testable import WeekclipData

/// The wire contract of the round trip, both directions.
///
/// Every assertion here is about a string a *different party* reads — GoTrue
/// for the outbound URL, the system for the inbound one — which is exactly the
/// class of thing that cannot be checked by running the app: a wrong parameter
/// name produces a sheet that opens, a prompt that completes, and a failure only
/// at the end.
@Suite("SupabaseOAuth")
struct SupabaseOAuthTests {

  private let config = AuthConfig(
    supabaseURL: URL(string: "https://project.supabase.co"),
    anonKey: "anon-key"
  )
  private let challenge = PkceChallenge(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")

  @Test("the authorize url carries the four parameters GoTrue needs")
  func authorizeParameters() throws {
    let url = try #require(SupabaseOAuth.authorizeURL(config: config, challenge: challenge))
    let items = try #require(
      URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
    )

    #expect(url.absoluteString.hasPrefix("https://project.supabase.co/auth/v1/authorize?"))
    #expect(items.contains(URLQueryItem(name: "provider", value: "google")))
    #expect(
      items.contains(URLQueryItem(name: "redirect_to", value: SupabaseOAuth.redirectURI)))
    #expect(
      items.contains(URLQueryItem(name: "code_challenge", value: challenge.challenge)))
    #expect(items.contains(URLQueryItem(name: "code_challenge_method", value: "s256")))
  }

  @Test("the redirect survives the URL intact, however it is escaped")
  func redirectRoundTrip() throws {
    let url = try #require(SupabaseOAuth.authorizeURL(config: config, challenge: challenge))
    let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)

    // What matters is the value GoTrue reads back, not the bytes on the way
    // there. `URLComponents` leaves `:` and `/` unescaped inside a query value
    // — legal per RFC 3986 §3.4 — while the Android twin's `URLEncoder`
    // escapes them. Asserting the decoded value keeps this test from pinning
    // one platform's escaping as the contract; a mismatch against Supabase's
    // allow list would show up as a byte-for-byte string difference, and there
    // is none.
    #expect(items.first { $0.name == "redirect_to" }?.value == SupabaseOAuth.redirectURI)

    // The one thing that genuinely must not appear unescaped: an `&` would end
    // the parameter early. None of the four values contains one today; this
    // asserts the URL still parses into exactly four items.
    #expect(items.count == 4)
  }

  @Test("the verifier never leaves the device")
  func verifierStaysLocal() throws {
    let url = try #require(SupabaseOAuth.authorizeURL(config: config, challenge: challenge))

    // The entire point of S256. If this ever fails, PKCE has become decoration.
    #expect(url.absoluteString.contains(challenge.verifier) == false)
  }

  @Test("a build with no project key has no url to open")
  func unconfigured() {
    let url = SupabaseOAuth.authorizeURL(
      config: AuthConfig(supabaseURL: URL(string: "https://project.supabase.co"), anonKey: ""),
      challenge: challenge
    )

    #expect(url == nil)
  }

  @Test("a redirect carrying a code is a grant")
  func grantedCallback() throws {
    let url = try #require(
      URL(string: "cc.sunglint.weekclip://auth-callback?code=1e0a4d6b-0000-0000-0000-000000000001")
    )

    #expect(
      SupabaseOAuth.parseCallback(url) == .granted(code: "1e0a4d6b-0000-0000-0000-000000000001"))
  }

  @Test("a refusal is read from either spelling of the error field")
  func deniedCallback() throws {
    // OAuth says `error`; GoTrue sends `error_code`. Which one arrives depends
    // on where in the chain the refusal happened, so both are read.
    let oauth = try #require(
      URL(
        string:
          "cc.sunglint.weekclip://auth-callback?error=access_denied&error_description=Not%20approved"
      ))
    #expect(
      SupabaseOAuth.parseCallback(oauth)
        == .denied(error: "access_denied", description: "Not approved"))

    let goTrue = try #require(
      URL(string: "cc.sunglint.weekclip://auth-callback?error_code=provider_disabled"))
    #expect(
      SupabaseOAuth.parseCallback(goTrue) == .denied(error: "provider_disabled", description: nil))
  }

  @Test("our own scheme with neither a code nor an error is not treated as success")
  func emptyCallback() throws {
    let url = try #require(URL(string: "cc.sunglint.weekclip://auth-callback?state=x"))

    #expect(SupabaseOAuth.parseCallback(url) == .denied(error: "missing_code", description: nil))
  }

  @Test("a universal link is not a callback")
  func universalLinkIsNotACallback() throws {
    // The two classifiers on the two platforms are meant to agree, and the
    // Android one is called on every incoming intent. A `code` query on a
    // weekclip.com URL must not be mistaken for our redirect either.
    #expect(
      SupabaseOAuth.parseCallback(try #require(URL(string: "https://weekclip.com/share/abc")))
        == .notACallback)
    #expect(
      SupabaseOAuth.parseCallback(
        try #require(URL(string: "https://weekclip.com/invite/abc?code=deadbeef")))
        == .notACallback)
  }

  @Test("a different host on our scheme is not a callback")
  func otherHostIsNotACallback() throws {
    // Leaves room for a second private-use route later without it silently
    // being read as a spent sign-in.
    #expect(
      SupabaseOAuth.parseCallback(
        try #require(URL(string: "cc.sunglint.weekclip://something-else?code=x")))
        == .notACallback)
  }

  @Test("a duplicated parameter cannot smuggle a second code past the first")
  func duplicateParameters() throws {
    let url = try #require(
      URL(string: "cc.sunglint.weekclip://auth-callback?code=real&code=injected"))

    #expect(SupabaseOAuth.parseCallback(url) == .granted(code: "real"))
  }
}
