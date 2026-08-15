import Foundation

/// Every failure the UI is allowed to see.
///
/// A closed set so a view can `switch` over it exhaustively and the compiler
/// catches a new case. Raw `Error` values leak `URLError` and
/// `DecodingError` into the presentation layer, and neither is something a
/// person can act on.
///
/// Carries no user-facing copy. Strings belong to the view layer so they are
/// localisable — and so `scripts/check-no-payment-strings.sh` has a bounded
/// place to look. **PRD-0008 D3: nothing in this app may name a way to pay.**
/// The previous version of this file ended `insufficientCapacity` with
/// "Please upgrade your plan or delete some content", which is exactly the
/// sentence Apple Guideline 3.1.1 is about; the case is gone until there is a
/// screen that needs to state the fact and stop there.
public enum AppError: Error, Equatable, Sendable {
  /// No usable network.
  case offline

  /// The request went out and nothing came back in time.
  case timeout

  /// 401/403 — the session is missing or no longer valid.
  ///
  /// The two fold together because the app's move is the same: get a session.
  /// Splitting them would give the UI a branch with no distinct action.
  case unauthorized

  /// 404 — gone, or never visible to this session.
  case notFound

  /// Any other non-2xx. `code` is the API's own error code when it sent one.
  case server(status: Int, code: String?, message: String?)

  /// 2xx that did not match the contract — a missing `data` envelope, or JSON
  /// that would not decode. Distinct from `.server` because it means *we* are
  /// wrong, and it should be loud in the log.
  case malformedResponse

  /// Nothing above fits. The description is for logs, never for a label.
  case unexpected(description: String)
}
