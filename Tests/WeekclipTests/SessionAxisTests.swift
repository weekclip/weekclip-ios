import Testing

@testable import WeekclipData

/// Which routes belong to which credential.
///
/// The paths come from weekclip-api's route table (`src/platform/app.ts`, lines
/// 437-446), not from imagination. The pair that matters is the last group:
/// both contain "share", and they sit on **opposite** axes.
@Suite("SessionAxis")
struct SessionAxisTests {

  @Test(
    "ordinary api routes are on the profile axis",
    arguments: [
      "/api/v1/studios",
      "/api/v1/studios/abc/media",
      "/api/v1/studios/abc/media/def",
      "/api/v1/auth/session",
    ])
  func profileRoutes(path: String) {
    #expect(SessionAxis.of(path: path) == .profile)
  }

  @Test(
    "the guest share surface is on the guest axis",
    arguments: [
      "/api/v1/share/tok/session",
      "/api/v1/share/tok/media",
      "/api/v1/share/tok/media/mid",
      "/api/v1/share/tok/media/mid/original",
    ])
  func guestRoutes(path: String) {
    #expect(SessionAxis.of(path: path) == .guest)
  }

  /// `/api/v1/studios/:id/share-links` is authenticated as the owner. A
  /// substring match on "share" would strip the bearer from the screen that
  /// creates and revokes share links — breaking the owner feature while trying
  /// to support the guest one.
  @Test(
    "owner-side share-link management stays on the profile axis",
    arguments: [
      "/api/v1/studios/abc/share-links",
      "/api/v1/studios/abc/share-links/xyz",
    ])
  func ownerShareLinkRoutes(path: String) {
    #expect(SessionAxis.of(path: path) == .profile)
  }

  @Test("a future api version keeps the same split")
  func futureVersion() {
    #expect(SessionAxis.of(path: "/api/v2/share/tok/media") == .guest)
    #expect(SessionAxis.of(path: "/api/v2/studios") == .profile)
  }
}
