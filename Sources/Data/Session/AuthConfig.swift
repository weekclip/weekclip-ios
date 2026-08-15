import Foundation

/// Where the app talks to Supabase's auth service, and with which project key.
///
/// Separate from `APIEndpoints` because it points at a different party: those
/// are weekclip's own Workers, this is the identity provider that mints the
/// token they verify.
///
/// ### The anon key is not a secret
///
/// It is a JWT carrying the `anon` role, and weekclip's own production web
/// bundle serves it to every visitor — `https://weekclip.com/assets/index-*.js`
/// contains it in cleartext next to the production project URL (checked
/// 2026-08-15). Row-level security is the boundary; the key is an addressing
/// detail. It still does not live in this repo: the superrepo's
/// `secrets/*.enc.yaml` is the value ledger, and it reaches the binary through
/// the build environment (`WEEKCLIP_SUPABASE_ANON_KEY_DEV`, see the README).
///
/// ### `isConfigured` is not defensive programming
///
/// The production key is deliberately absent. Release builds have no way to
/// sign in at all — the product's only login is Google OAuth (weekclip-web
/// `LoginPage.tsx`), which needs OAuth clients registered per platform, tracked
/// as 148.5c-b. Rather than ship a production credential-shaped string nothing
/// can use yet, the refresher asks this first and reports a clean sign-out
/// instead of firing a request Supabase would answer with a confusing 401.
public struct AuthConfig: Sendable {
  public let supabaseURL: URL?
  public let anonKey: String

  public init(supabaseURL: URL?, anonKey: String) {
    self.supabaseURL = supabaseURL
    self.anonKey = anonKey
  }

  public var isConfigured: Bool { supabaseURL != nil && !anonKey.isEmpty }

  /// GoTrue lives under `/auth/v1`.
  public var tokenBaseURL: URL? {
    supabaseURL?.appendingPathComponent("auth").appendingPathComponent("v1")
  }

  /// The dev project. Note the URL is committed — it is already in every
  /// service's `wrangler.jsonc`, because an address is not a credential.
  public static func development(anonKey: String) -> AuthConfig {
    AuthConfig(
      supabaseURL: URL(string: "https://uwygkfgdpglwblkmndtc.supabase.co"),
      anonKey: anonKey
    )
  }

  public static func production(anonKey: String) -> AuthConfig {
    AuthConfig(
      supabaseURL: URL(string: "https://pmkuddfuwdbvsjwudgii.supabase.co"),
      anonKey: anonKey
    )
  }

  /// Picked by build configuration rather than by a runtime flag, so a release
  /// build cannot be talked into the dev project by anything on the device.
  ///
  /// The key arrives through `Info.plist`, which XcodeGen fills from the build
  /// environment. An absent key yields `isConfigured == false`, which every
  /// caller already handles.
  public static var current: AuthConfig {
    let key = (Bundle.main.object(forInfoDictionaryKey: "WeekclipSupabaseAnonKey") as? String) ?? ""
    #if DEBUG
    return .development(anonKey: key)
    #else
    return .production(anonKey: key)
    #endif
  }
}
