import Foundation

extension TimeInterval {
  /// Formatted time string in MM:SS format
  var formattedTime: String {
    guard !isNaN && !isInfinite else { return "0:00" }

    let minutes = Int(self) / 60
    let seconds = Int(self) % 60
    return String(format: "%d:%02d", minutes, seconds)
  }

  /// Formatted time string in HH:MM:SS format
  var formattedTimeWithHours: String {
    guard !isNaN && !isInfinite else { return "0:00:00" }

    let hours = Int(self) / 3600
    let minutes = (Int(self) % 3600) / 60
    let seconds = Int(self) % 60
    return String(format: "%d:%02d:%02d", hours, minutes, seconds)
  }
}
