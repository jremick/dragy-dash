import Foundation

struct TelemetryMotionEstimator {
  private let movementThresholdKPH = 5.0
  private let standardGravity = 9.80665
  private var previous: TelemetrySnapshot?

  mutating func apply(to snapshot: TelemetrySnapshot) -> TelemetrySnapshot {
    var enriched = snapshot

    defer {
      previous = snapshot
    }

    guard let previous else {
      return enriched
    }

    let elapsed = snapshot.timestamp.timeIntervalSince(previous.timestamp)
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
