import Foundation

/// The two pure ends of the Google sign-in round trip: the URL the browser is
/// sent to, and what comes back.
///
/// ### No Google OAuth client of our own is involved
///
/// This is the assumption that made 148.5c-b look blocked. The app does **not**
/// talk to Google. It opens *Supabase's* `/auth/v1/authorize`; Supabase
/// redirects to Google with **Supabase's own web client id**; Google redirects
/// back to **Supabase's** HTTPS callback. Only then does Supabase redirect to
/// `redirectURI`. Google never sees a custom scheme, so there is no iOS or
/// Android OAuth client to register — measured 2026-08-16: the dev project's
/// `/authorize?provider=google` answers 302 to `accounts.google.com` with
/// `redirect_uri=https://<project>.supabase.co/auth/v1/callback`.
///
/// What *is* required is one console line per project: `redirectURI` has to be
/// in Supabase Auth's **Redirect URLs** allow list. GoTrue validates
/// `redirect_to` at callback time, not at `/authorize` time — so a missing
/// entry looks like a browser that completes the Google prompt and then sits on
/// the website instead of returning, with no error anywhere.
///
/// Everything here is pure: no `UIKit`, no network, no storage. That is what
/// lets the wire format be pinned by tests rather than by a simulator.
///
/// Mirrors `core/auth/SupabaseOAuth.kt` in weekclip-android.
public enum SupabaseOAuth {

  /// Where Supabase sends the browser once it has the grant.
  ///
  /// The scheme is the bundle identifier, the convention that keeps two apps
  /// from colliding by accident (RFC 8252 §7.1). A convention, not a guarantee
  /// — `PkceChallenge` is what actually makes the redirect safe.
  ///
  /// Handed to `ASWebAuthenticationSession` as its `callbackURLScheme`, and it
  /// must stay byte-identical to the Supabase allow-list entry: GoTrue compares
  /// the string, so a trailing slash is a different URL.
  public static let redirectURI = "cc.sunglint.weekclip://auth-callback"

  /// The scheme half of `redirectURI`, which is what the system needs on its own.
  public static let callbackScheme = "cc.sunglint.weekclip"

  /// The one provider weekclip offers (weekclip-web `LoginPage.tsx`).
  public static let providerGoogle = "google"

  /// The URL to hand to the system browser.
  ///
  /// - Returns: nil when this build has no Supabase project compiled in.
  ///   Release builds shipped that way on purpose until the production anon key
  ///   reached the ledger (see `AuthConfig`), and nil keeps the caller from
  ///   presenting a sheet pointing at nothing.
  public static func authorizeURL(
    config: AuthConfig,
    challenge: PkceChallenge,
    provider: String = providerGoogle,
    redirectURI: String = redirectURI
  ) -> URL? {
    guard config.isConfigured, let base = config.tokenBaseURL else { return nil }

    guard
      var components = URLComponents(
        url: base.appendingPathComponent("authorize"),
        resolvingAgainstBaseURL: false
      )
    else { return nil }

    // `URLComponents` leaves `:` and `/` alone inside a query value, so
    // `redirect_to` goes out reading `cc.sunglint.weekclip://auth-callback`
    // verbatim. That is **correct** — RFC 3986 §3.4 allows both in a query, and
    // only `&` and `=` delimit — and it is worth stating because the Android
    // twin uses `URLEncoder`, which escapes them. Two different spellings of the
    // same value; GoTrue decodes either. `SupabaseOAuthTests` asserts the
    // decoded value rather than the bytes, so neither platform's test is pinned
    // to its own escaping.
    components.queryItems = [
      URLQueryItem(name: "provider", value: provider),
      URLQueryItem(name: "redirect_to", value: redirectURI),
      URLQueryItem(name: "code_challenge", value: challenge.challenge),
      URLQueryItem(name: "code_challenge_method", value: PkceChallenge.method),
    ]

    return components.url
  }

  /// Classifies a URL the system handed back.
  ///
  /// Anything that is not our redirect — a Universal Link, a stray scheme —
  /// comes back as `.notACallback` rather than throwing, because on the Android
  /// side the equivalent is called on *every* incoming intent and the two
  /// classifiers are meant to agree.
  public static func parseCallback(_ url: URL) -> OAuthCallback {
    guard
      let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      components.scheme == callbackScheme,
      components.host == "auth-callback"
    else {
      return .notACallback
    }

    // First wins. A duplicated parameter is an attempt to confuse the reader,
    // and a dictionary built by overwriting would silently prefer the last.
    var params: [String: String] = [:]
    for item in components.queryItems ?? [] where params[item.name] == nil {
      params[item.name] = item.value
    }

    if let code = params["code"], !code.isEmpty {
      return .granted(code: code)
    }

    // GoTrue names the machine-readable field `error_code` and the OAuth spec
    // names it `error`; which one arrives depends on where in the chain the
    // refusal happened. Reading whichever is present beats guessing.
    if let error = params["error_code"] ?? params["error"] {
      return .denied(error: error, description: params["error_description"])
    }

    // Our scheme, our host, and neither a code nor an error. Not something to
    // guess at.
    return .denied(error: "missing_code", description: nil)
  }
}

/// What a redirect back into the app turned out to be.
public enum OAuthCallback: Equatable, Sendable {
  /// Supabase issued an authorization code. It still has to be exchanged.
  case granted(code: String)

  /// The round trip finished and there is no code — the user declined at
  /// Google's prompt, or the provider refused.
  case denied(error: String, description: String?)

  /// Not our redirect at all. The caller should ignore it.
  case notACallback
}
