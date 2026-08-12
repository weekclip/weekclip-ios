import XCTest
@testable import WeekclipDomain

final class GetMediaUseCaseTests: XCTestCase {
  var useCase: GetMediaUseCase!

  override func setUp() {
    super.setUp()
    useCase = GetMediaUseCase()
  }

  func testCallAsFunction() async throws {
    let result = try await useCase()
    XCTAssertEqual(result.count, 0)
  }
}
