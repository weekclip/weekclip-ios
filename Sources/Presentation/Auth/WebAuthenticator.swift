import AuthenticationServices
import Foundation
import WeekclipShared

/// Runs the browser half of the OAuth round trip.
///
/// A protocol so the login view model can be driven without a window. The real
/// implementation below is the only thing in this feature that cannot be
/// tested off a device, and it is deliberately three lines of logic — everything
/// worth getting wrong lives in `SupabaseOAuth` and `PkceChallenge`, which are
/// pure.
@MainActor
public protocol WebAuthenticating: Sendable {
  /// - Returns: the redirect URL the system intercepted.
  /// - Throws: `WebAuthenticationError.cancelled` when the user dismissed the
  ///   sheet, and `.failed` for anything else.
  func authenticate(url: URL, callbackScheme: String) async throws -> URL
}

public enum WebAuthenticationError: Error, Equatable, Sendable {
  case cancelled
  case failed(description: String)
}

/// `ASWebAuthenticationSession`.
///
/// **Not a `WKWebView`**, and not a style preference: Google refuses OAuth from
/// an embedded web view (`disallowed_useragent`), because an embedded view can
/// read the password as it is typed. RFC 8252 §8.12 says the same in general
/// terms. This is Safari's engine, running out of process, holding whatever
/// Google session the user already has — which is why most people never see a
/// password prompt at all.
///
/// ### The one place iOS is simpler than Android
///
/// The system intercepts the redirect by `callbackURLScheme` and hands it back
/// through this callback, so there is no `Info.plist` URL type, no
/// `onOpenURL` branch, and — the part that matters — **cancellation is
/// reported**. `ASWebAuthenticationSessionError.canceledLogin` arrives when the
/// user taps Cancel. The Android twin has to infer the same fact from an empty
/// slot at `onResume`, because that platform sends no event at all; see
/// `AuthRedirectBus` there. Same product behaviour, and only one of the two is
/// an inference.
///
/// `prefersEphemeralWebBrowserSession` is left **off**. On it, the sheet starts
/// with no cookies, so a user already signed in to Google would have to type a
/// password every time — which is the cost the flow exists to avoid.
@MainActor
public final class WebAuthenticator: NSObject, WebAuthenticating {

  public override init() {
    super.init()
  }

  public func authenticate(url: URL, callbackScheme: String) async throws -> URL {
    // A stored strong reference is required: ASWebAuthenticationSession
    // cancels itself on deallocation, and a local `let` inside the closure
    // below is not guaranteed to outlive the suspension.
    var session: ASWebAuthenticationSession?

    return try await withCheckedThrowingContinuation { continuation in
      let created = ASWebAuthenticationSession(
        url: url,
        callbackURLScheme: callbackScheme
      ) { callbackURL, error in
        if let error {
          let code = (error as? ASWebAuthenticationSessionError)?.code
          continuation.resume(
            throwing: code == .canceledLogin
              ? WebAuthenticationError.cancelled
              : WebAuthenticationError.failed(description: String(describing: error))
          )
          return
        }
        guard let callbackURL else {
          // Documented as impossible — no error and no URL — but resuming a
          // continuation zero times hangs the caller for the life of the
          // process, which is worse than any wrong branch.
          continuation.resume(
            throwing: WebAuthenticationError.failed(description: "no callback URL and no error")
          )
          return
        }
        continuation.resume(returning: callbackURL)
      }

      created.presentationContextProvider = self
      session = created

      if !created.start() {
        continuation.resume(
          throwing: WebAuthenticationError.failed(description: "could not start the session")
        )
      }
      _ = session
    }
  }
}

extension WebAuthenticator: ASWebAuthenticationPresentationContextProviding {
  public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
    // The key window of the active foreground scene. Falling back to a fresh
    // `ASPresentationAnchor()` rather than crashing: this is called while the
    // app is on screen, so the nil path is unreachable, and a `fatalError` on
    // an unreachable path is a crash report waiting to be caused by an OS
    // change.
    let scene = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }

    guard let anchor = scene?.keyWindow ?? scene?.windows.first else {
      AppLog.session.error("no foreground window to present the sign-in sheet from")
      return ASPresentationAnchor()
    }
    return anchor
  }
}
