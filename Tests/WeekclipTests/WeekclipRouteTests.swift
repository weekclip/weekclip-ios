import Foundation
import Testing

@testable import WeekclipPresentation

/// The route table is a cross-repo contract: these exact strings must match
/// `WeekclipRoutes` in weekclip-android and the URLs weekclip-web serves. A
/// mismatch does not fail anywhere else — it fails as a Universal Link that
/// silently opens Safari instead of the app, on someone else's phone.
///
/// So the literals below are written out rather than derived. Deriving them
/// from `WeekclipRoute` itself would make this test agree with any change,
/// including a wrong one.
@Suite("WeekclipRoute")
struct WeekclipRouteTests {

  @Test("every route builds the path the web and Android use")
  func pathsMatchTheContract() {
    #expect(WeekclipRoute.dashboard.path == "dashboard")
    #expect(WeekclipRoute.studio(id: "st_1").path == "studios/st_1")
    #expect(
      WeekclipRoute.media(studioID: "st_1", mediaID: "md_2").path == "studios/st_1/media/md_2")
    #expect(WeekclipRoute.members(studioID: "st_1").path == "studios/st_1/members")
    #expect(WeekclipRoute.capacity(studioID: "st_1").path == "studios/st_1/capacity")
    #expect(WeekclipRoute.invite(token: "tok").path == "invite/tok")
    #expect(WeekclipRoute.share(token: "tok").path == "share/tok")
  }

  @Test(
    "every route round-trips through its own path",
    arguments: [
      WeekclipRoute.dashboard,
      .studio(id: "st_1"),
      .media(studioID: "st_1", mediaID: "md_2"),
      .members(studioID: "st_1"),
      .capacity(studioID: "st_1"),
      .invite(token: "tok"),
      .share(token: "tok"),
    ]
  )
  func roundTrips(route: WeekclipRoute) {
    #expect(WeekclipRoute(path: route.path) == route)
  }

  @Test("a leading slash parses the same — Universal Links arrive with one")
  func leadingSlashIsAccepted() {
    #expect(
      WeekclipRoute(path: "/studios/st_1/media/md_2") == .media(studioID: "st_1", mediaID: "md_2"))
  }

  @Test("a full Universal Link resolves to its route")
  func parsesAUniversalLink() {
    let url = URL(string: "https://weekclip.com/studios/st_1/media/md_2")!
    #expect(WeekclipRoute(url: url) == .media(studioID: "st_1", mediaID: "md_2"))
  }

  @Test("a query string does not change which route it is")
  func ignoresQueryParameters() {
    let url = URL(string: "https://weekclip.com/invite/tok?utm_source=kakao")!
    #expect(WeekclipRoute(url: url) == .invite(token: "tok"))
  }

  @Test(
    "paths this app does not own return nil rather than a guess",
    arguments: ["", "/", "/pricing", "/studios", "/studios/st_1/media", "/studios/st_1/unknown"]
  )
  func unownedPathsReturnNil(path: String) {
    // PRD-0008 D4 keeps public pages on the web. Guessing a route here would
    // swallow a link the browser should have handled.
    #expect(WeekclipRoute(path: path) == nil)
  }
}
