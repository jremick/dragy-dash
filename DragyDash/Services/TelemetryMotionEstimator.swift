import Foundation

struct TelemetryMotionEstimator: Sendable {
  private let movementThresholdKPH = 5.0
  private let standardGravity = 9.80665
  private var previous: TelemetrySnapshot?

  mutating func apply(to snapshot: TelemetrySnapshot) -> TelemetrySnapshot {
    var enriched = snapshot

    guard snapshot.isUsableFix else {
      previous = nil
      return enriched
    }

    defer {
      previous = snapshot
    }

    guard let previous, previous.isUsableFix else {
      return enriched
    }

    let elapsed = Self.elapsedSeconds(from: previous, to: snapshot)
    guard elapsed > 0.05, elapsed <= 2 else {
      return enriched
    }

    if max(snapshot.speedKPH, previous.speedKPH) < movementThresholdKPH {
      enriched.longitudinalG = enriched.longitudinalG ?? 0
      enriched.lateralG = enriched.lateralG ?? 0
      enriched.yawRateDegreesPerSecond = enriched.yawRateDegreesPerSecond ?? 0
      return enriched
    }

    let speedMetersPerSecond = snapshot.speedKPH / 3.6
    let previousSpeedMetersPerSecond = previous.speedKPH / 3.6
    let longitudinalAcceleration = (speedMetersPerSecond - previousSpeedMetersPerSecond) / elapsed
    enriched.longitudinalG = enriched.longitudinalG ?? longitudinalAcceleration / standardGravity

    if let heading = snapshot.headingDegrees,
       let previousHeading = previous.headingDegrees {
      let yawRate = normalizedHeadingDelta(from: previousHeading, to: heading) / elapsed
      let averageSpeedMetersPerSecond = (speedMetersPerSecond + previousSpeedMetersPerSecond) / 2

      enriched.yawRateDegreesPerSecond = enriched.yawRateDegreesPerSecond ?? yawRate
      enriched.lateralG = enriched.lateralG ?? averageSpeedMetersPerSecond * yawRate * .pi / 180 / standardGravity
    }

    return enriched
  }

  mutating func reset() {
    previous = nil
  }

  static func elapsedSeconds(from previous: TelemetrySnapshot, to current: TelemetrySnapshot) -> TimeInterval {
    if let prevTOW = previous.gpsTimeOfWeekMS, let currTOW = current.gpsTimeOfWeekMS, currTOW != prevTOW {
      let weekMS: UInt32 = 604_800_000
      let deltaMS: UInt32
      if currTOW >= prevTOW {
        deltaMS = currTOW - prevTOW
      } else {
        deltaMS = (weekMS &- prevTOW) &+ currTOW
      }

      let seconds = Double(deltaMS) / 1000.0
      if seconds > 0, seconds < 10 {
        return seconds
      }
    }

    return current.timestamp.timeIntervalSince(previous.timestamp)
  }

  private func normalizedHeadingDelta(from previous: Double, to current: Double) -> Double {
    var delta = current - previous

    while delta > 180 {
      delta -= 360
    }

    while delta < -180 {
      delta += 360
    }

    return delta
  }
}
