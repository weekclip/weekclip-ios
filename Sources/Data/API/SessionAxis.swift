import Foundation

/// Which credential a given request is supposed to carry.
///
/// weekclip has **two authentication axes that share one header**, and the app
/// has to pick between them per request. This is not a design the app chose; it
/// is the API's:
///
/// | axis | credential | verified by |
/// |------|-----------|-------------|
/// | `profile` | Supabase access token (JWT) | remote JWKS — `supabase-token-verifier.ts` |
/// | `guest` | share-link session token (`payload.signature`, HMAC) | the share link's own `sessionKey` — `share-link-session.ts` |
///
/// Both arrive as `Authorization: Bearer …` — `studio-share-link-controller.ts`
/// slices the same prefix — so nothing about the transport distinguishes them.
/// Only the route does.
///
/// **Sending the wrong one is not harmless.** A signed-in user opening a share
/// link would have their profile JWT put on `/share/:token/media`, where the
/// server tries to HMAC-verify it against the link's key, fails, and answers
/// 401. The user is told they cannot view a link that works fine in a browser —
/// and the app's refresh logic then chases a token that was never the problem.
///
/// PRD-0008 D5 is what puts weekclip here: guests are required to install the
/// app, so the guest surface has to exist natively rather than be left to web.
public enum SessionAxis: Equatable, Sendable {
  case profile
  case guest

  /// `/api/v1/share/...` is the guest surface. Everything else is profile.
  ///
  /// Anchored at the version segment on purpose: the owner-side routes
  /// `/api/v1/studios/:id/share-links` are *profile*-authenticated and also
  /// contain the word "share". A substring match would silently strip the
  /// bearer from the screen that lists a studio's share links.
  public static func of(path: String) -> SessionAxis {
    guestPath.firstMatch(
      in: path,
      range: NSRange(path.startIndex..., in: path)
    ) == nil ? .profile : .guest
  }

  private static let guestPath = try! NSRegularExpression(pattern: #"/api/v\d+/share/"#)
}
