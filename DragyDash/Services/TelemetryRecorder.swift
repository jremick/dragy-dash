import Foundation

final class TelemetryRecorder {
  private(set) var samples: [TelemetrySnapshot] = []
  private(set) var stats = TelemetryRunStats.empty
  private var statsSamples: [TelemetrySnapshot] = []
  private var lastStatsSample: TelemetrySnapshot?
  private let maxStoredSamples: Int
  private let maxAverageSamples: Int
  private let maxAverageWindowDistanceMeters: Double

  init(
    maxStoredSamples: Int = 18_000,
    maxAverageSamples: Int = 36_000,
    maxAverageWindowDistanceMeters: Double = 15_000
  ) {
    self.maxStoredSamples = maxStoredSamples
    self.maxAverageSamples = maxAverageSamples
    self.maxAverageWindowDistanceMeters = maxAverageWindowDistanceMeters
  }

  func start(at date: Date = .now) {
    stats.isRecording = true
    if stats.startedAt == nil {
      stats.startedAt = date
    }
  }

  func stop() {
    stats.isRecording = false
  }

  func reset(startRecording: Bool, at date: Date = .now) {
    samples = []
    statsSamples = []
    lastStatsSample = nil
    stats = .empty
    if startRecording {
      start(at: date)
    }
  }

  func record(_ snapshot: TelemetrySnapshot) {
    record(raw: snapshot, statsSnapshot: snapshot)
  }

  func record(raw snapshot: TelemetrySnapshot, statsSnapshot: TelemetrySnapshot) {
    guard stats.isRecording else {
      return
    }

    if stats.startedAt == nil {
      stats.startedAt = snapshot.timestamp
    }

    if let startedAt = stats.startedAt {
      stats.elapsedSeconds = max(0, snapshot.timestamp.timeIntervalSince(startedAt))
    }

    let hasUsableFix = statsSnapshot.fixQuality != .none

    if hasUsableFix, let lastStatsSample {
      updateDistance(from: lastStatsSample, to: statsSnapshot)
      updateAccelerationTargets(from: lastStatsSample, to: statsSnapshot)
    }

    samples.append(snapshot)
    pruneStoredSamples()
    stats.sampleCount += 1

    guard hasUsableFix else {
      lastStatsSample = nil
      return
    }

    statsSamples.append(statsSnapshot)
    pruneAverageSamples()
    stats.peakSpeedKPH = max(stats.peakSpeedKPH, statsSnapshot.speedKPH)
    stats.maxLongitudinalG = maxMagnitude(stats.maxLongitudinalG, statsSnapshot.longitudinalG)
    stats.maxLateralG = maxMagnitude(stats.maxLateralG, statsSnapshot.lateralG)
    updateDistanceAverages()
    self.lastStatsSample = statsSnapshot
  }

  private func updateDistance(from previous: TelemetrySnapshot, to current: TelemetrySnapshot) {
    let elapsed = current.timestamp.timeIntervalSince(previous.timestamp)
    guard elapsed > 0, elapsed < 10 else {
      return
    }

    let averageMetersPerSecond = ((previous.speedKPH + current.speedKPH) / 2) / 3.6
    stats.distanceMeters += averageMetersPerSecond * elapsed
  }

  private func updateAccelerationTargets(from previous: TelemetrySnapshot, to current: TelemetrySnapshot) {
    guard let startedAt = stats.startedAt else {
      return
    }

    if stats.zeroToSixtyKPHSeconds == nil {
      stats.zeroToSixtyKPHSeconds = crossingTime(
        targetKPH: 60,
        previous: previous,
        current: current,
        startedAt: startedAt
      )
    }

    if stats.zeroToSixtyMPHSeconds == nil {
      stats.zeroToSixtyMPHSeconds = crossingTime(
        targetKPH: 60 / 0.621371,
        previous: previous,
        current: current,
        startedAt: startedAt
      )
    }

    if stats.zeroToOneHundredKPHSeconds == nil {
      stats.zeroToOneHundredKPHSeconds = crossingTime(
        targetKPH: 100,
        previous: previous,
        current: current,
        startedAt: startedAt
      )
    }

    if stats.zeroToOneHundredMPHSeconds == nil {
      stats.zeroToOneHundredMPHSeconds = crossingTime(
        targetKPH: 100 / 0.621371,
        previous: previous,
        current: current,
        startedAt: startedAt
      )
    }
  }

  private func crossingTime(
    targetKPH: Double,
    previous: TelemetrySnapshot,
    current: TelemetrySnapshot,
    startedAt: Date
  ) -> TimeInterval? {
    guard previous.speedKPH < targetKPH, current.speedKPH >= targetKPH else {
      return nil
    }

    let deltaSpeed = current.speedKPH - previous.speedKPH
    guard deltaSpeed > 0 else {
      return nil
    }

    let fraction = (targetKPH - previous.speedKPH) / deltaSpeed
    let elapsedBetweenSamples = current.timestamp.timeIntervalSince(previous.timestamp)
    let crossingDate = previous.timestamp.addingTimeInterval(elapsedBetweenSamples * fraction)
    return crossingDate.timeIntervalSince(startedAt)
  }

  private func updateDistanceAverages() {
    stats.averageSpeedLast1KMKPH = averageSpeed(overDistanceMeters: 1_000)
    stats.averageSpeedLast5KMKPH = averageSpeed(overDistanceMeters: 5_000)
    stats.averageSpeedLast10KMKPH = averageSpeed(overDistanceMeters: 10_000)
    stats.averageSpeedLast1MileKPH = averageSpeed(overDistanceMeters: 1_609.344)
    stats.averageSpeedLast3MilesKPH = averageSpeed(overDistanceMeters: 4_828.032)
    stats.averageSpeedLast5MilesKPH = averageSpeed(overDistanceMeters: 8_046.72)
  }

  private func pruneStoredSamples() {
    let overflow = samples.count - maxStoredSamples
    if overflow > 0 {
      samples.removeFirst(overflow)
    }
  }

  private func pruneAverageSamples() {
    guard statsSamples.count > 2 else {
      return
    }

    var accumulatedDistance = 0.0
    var keepStartIndex = statsSamples.count - 1

    for index in stride(from: statsSamples.count - 1, through: 1, by: -1) {
      accumulatedDistance += distance(from: statsSamples[index - 1], to: statsSamples[index])
      keepStartIndex = index - 1

      if accumulatedDistance >= maxAverageWindowDistanceMeters {
        break
      }
    }

    if keepStartIndex > 0 {
      statsSamples.removeFirst(keepStartIndex)
    }

    let overflow = statsSamples.count - maxAverageSamples
    if overflow > 0 {
      statsSamples.removeFirst(overflow)
    }
  }

  private func averageSpeed(overDistanceMeters targetDistanceMeters: Double) -> Double? {
    guard statsSamples.count >= 2 else {
      return nil
    }

    let endDate = statsSamples[statsSamples.count - 1].timestamp
    let distanceToleranceMeters = 0.01
    var remainingDistance = targetDistanceMeters

    for index in stride(from: statsSamples.count - 1, through: 1, by: -1) {
      let current = statsSamples[index]
      let previous = statsSamples[index - 1]
      let elapsed = current.timestamp.timeIntervalSince(previous.timestamp)
      guard elapsed > 0, elapsed < 10 else {
        continue
      }

      let segmentDistance = distance(from: previous, to: current)
      guard segmentDistance > 0 else {
        continue
      }

      if segmentDistance + distanceToleranceMeters >= remainingDistance {
        let distanceInsideSegment = min(remainingDistance, segmentDistance)
        let elapsedInsideSegment = elapsed * (distanceInsideSegment / segmentDistance)
        let startDate = current.timestamp.addingTimeInterval(-elapsedInsideSegment)
        let totalElapsed = endDate.timeIntervalSince(startDate)
        guard totalElapsed > 0 else {
          return nil
        }
        return targetDistanceMeters / totalElapsed * 3.6
      }

      remainingDistance -= segmentDistance
    }

    return nil
  }

  private func distance(from previous: TelemetrySnapshot, to current: TelemetrySnapshot) -> Double {
    let elapsed = current.timestamp.timeIntervalSince(previous.timestamp)
    guard elapsed > 0, elapsed < 10 else {
      return 0
    }

    let averageMetersPerSecond = ((previous.speedKPH + current.speedKPH) / 2) / 3.6
    return averageMetersPerSecond * elapsed
  }

  private func maxMagnitude(_ current: Double?, _ candidate: Double?) -> Double? {
    guard let candidate else {
      return current
    }

    guard let current else {
      return candidate
    }

    return abs(candidate) > abs(current) ? candidate : current
  }
}

struct TelemetrySessionExporter {
  static func csv(samples: [TelemetrySnapshot]) -> String {
    let header = [
      "timestamp",
      "speed_kph",
      "speed_mph",
      "heading_degrees",
      "latitude",
      "longitude",
      "altitude_meters",
      "horizontal_accuracy_meters",
      "satellite_count",
      "fix_quality",
      "longitudinal_g",
      "lateral_g",
      "vertical_g",
      "yaw_rate_degrees_per_second",
      "source"
    ].joined(separator: ",")

    let rows = samples.map { sample in
      [
        DragyDateFormatter.string(from: sample.timestamp),
        sample.speedKPH.csvValue(decimals: 3),
        sample.speedMPH.csvValue(decimals: 3),
        sample.headingDegrees.csvValue(decimals: 3),
        sample.latitude.csvValue(decimals: 7),
        sample.longitude.csvValue(decimals: 7),
        sample.altitudeMeters.csvValue(decimals: 3),
        sample.horizontalAccuracyMeters.csvValue(decimals: 3),
        sample.satelliteCount.map(String.init) ?? "",
        sample.fixQuality.rawValue,
        sample.longitudinalG.csvValue(decimals: 4),
        sample.lateralG.csvValue(decimals: 4),
        sample.verticalG.csvValue(decimals: 4),
        sample.yawRateDegreesPerSecond.csvValue(decimals: 4),
        sample.sourceName.csvEscaped
      ].joined(separator: ",")
    }

    return ([header] + rows).joined(separator: "\n")
  }
}

enum DragyDateFormatter {
  static func string(from date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
  }
}

private extension Optional where Wrapped == Double {
  func csvValue(decimals: Int) -> String {
    guard let self else {
      return ""
    }

    return self.csvValue(decimals: decimals)
  }
}

private extension Double {
  func csvValue(decimals: Int) -> String {
    String(format: "%.\(decimals)f", self)
  }
}

private extension String {
  var csvEscaped: String {
    if contains(",") || contains("\"") || contains("\n") {
      return "\"\(replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    return self
  }
}
