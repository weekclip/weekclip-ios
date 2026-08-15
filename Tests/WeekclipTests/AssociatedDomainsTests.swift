import Foundation
import Testing

/// The entitlement half of Universal Links (PRD-0008 D4 / N2).
///
/// The other half — `apple-app-site-association` on weekclip.com — is asserted
/// in weekclip-web, against the same claimed paths. Neither side can verify the
/// other at build time, so each pins its own end and names the other.
///
/// This is worth a test because the failure is silent: a typo in the domain, a
/// missing entitlement, or a `mode=developer` left in by accident produces an
/// app that builds, installs, runs, and simply never receives a link.
@Suite("associated domains entitlement")
struct AssociatedDomainsTests {

  private var entitlements: [String: Any] {
    // Read from source rather than from the built bundle: the entitlement is
    // applied at signing time and a simulator build is not signed the same way,
    // so reading the bundle would test the toolchain, not the checked-in spec.
    let url = URL(fileURLToPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("App/Weekclip.entitlements")
    guard
      let data = try? Data(contentsOf: url),
      let plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
        as? [String: Any]
    else {
      return [:]
    }
    return plist
  }

  @Test("claims weekclip.com for applinks")
  func claimsProductionDomain() {
    let domains = entitlements["com.apple.developer.associated-domains"] as? [String]

    #expect(domains == ["applinks:weekclip.com"])
  }

  /// `?mode=developer` makes the device fetch the association file directly
  /// instead of through Apple's CDN. It is a development affordance, and
  /// shipping it would mean the store build resolves links differently from the
  /// one that was tested.
  @Test("ships no developer-mode override")
  func noDeveloperMode() {
    let domains = entitlements["com.apple.developer.associated-domains"] as? [String] ?? []

    for domain in domains {
      #expect(!domain.contains("mode=developer"), "\(domain) carries a developer-only override")
    }
  }
}

extension URL {
  fileprivate init(fileURLToPath path: StaticString) {
    self.init(fileURLWithPath: "\(path)")
  }
}
