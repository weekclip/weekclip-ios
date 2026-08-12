import AVFoundation

extension AVPlayer {
  /// Current playback time in seconds
  var currentTimeInSeconds: Double {
    currentTime().seconds
  }

  /// Set current playback time
  func setCurrentTime(_ seconds: Double) {
    let cmTime = CMTime(seconds: seconds, preferredTimescale: 1000)
    seek(to: cmTime)
  }

  /// Get buffered duration
  var bufferedDuration: Double {
    guard let currentItem = currentItem else { return 0 }

    let loadedRanges = currentItem.loadedTimeRanges
    guard !loadedRanges.isEmpty else { return 0 }

    if let timeRange = loadedRanges.last?.timeRangeValue {
      let bufferedStart = timeRange.start.seconds
      let bufferedDurationValue = timeRange.duration.seconds
      return bufferedStart + bufferedDurationValue
    }

    return 0
  }
}
