import XCTest
@testable import WeekclipData

final class WeekclipAPIClientTests: XCTestCase {
  func testDefaultBaseURLPointsAtDevAPI() {
    let client = WeekclipAPIClient()
    XCTAssertEqual(
      Mirror(reflecting: client).descendant("baseURL") as? URL,
      URL(string: "https://dev-service-api.weekclip.com/api/v1")
    )
  }

  func testCustomBaseURLIsRetained() {
    let url = URL(string: "https://example.test/api/v2")!
    let client = WeekclipAPIClient(baseURL: url)
    XCTAssertEqual(Mirror(reflecting: client).descendant("baseURL") as? URL, url)
  }
}
