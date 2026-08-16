import SwiftUI
import UIKit

/// UIKit-backed chrome that SwiftUI cannot restyle from a modifier.
///
/// `.navigationTitle` renders inside a `UINavigationBar`, and SwiftUI exposes
/// no way to give that title a font — `.font()` on the view does not reach it.
/// So the navigation bar keeps San Francisco no matter how much of the body is
/// branded, and on the dashboard the largest text on screen is the title.
/// Measured on the simulator before this existed: the mark and the accent had
/// landed and "Studios" was still SF Pro.
///
/// The appearance proxy is the supported way in. It has to be applied before
/// the first bar is created, which is why ``RootView`` calls it from `init`
/// rather than from `onAppear`.
public enum WeekclipAppearance {

  /// Idempotent — the proxy holds the last value written, and writing the same
  /// value twice costs nothing.
  @MainActor
  public static func apply() {
    let appearance = UINavigationBarAppearance()
    appearance.configureWithDefaultBackground()

    // Scaled through UIFontMetrics rather than set at a fixed point size, for
    // the same reason `Font.weekclip` passes `relativeTo:` — a hard-coded size
    // here would make the one piece of chrome that ignores Dynamic Type also
    // the biggest text on the screen.
    if let largeTitle = UIFont(name: WeekclipFontName.spaceGroteskMedium.rawValue, size: 34) {
      appearance.largeTitleTextAttributes = [
        .font: UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: largeTitle)
      ]
    }
    if let title = UIFont(name: WeekclipFontName.spaceGroteskMedium.rawValue, size: 17) {
      appearance.titleTextAttributes = [
        .font: UIFontMetrics(forTextStyle: .headline).scaledFont(for: title)
      ]
    }

    // All three, or the bar changes face when the content scrolls under it.
    let proxy = UINavigationBar.appearance()
    proxy.standardAppearance = appearance
    proxy.scrollEdgeAppearance = appearance
    proxy.compactAppearance = appearance
  }
}
