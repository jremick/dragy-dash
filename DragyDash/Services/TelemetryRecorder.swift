import Foundation

final class TelemetryRecorder {
  var samples: [TelemetrySnapshot] {
    sampleRing.elements
  }

  var hasSamples: Bool {
    !sampleRing.isEmpty
  }

  private(set) var stats = TelemetryRunStats.empty

  private var sampleRing: SampleRingBuffer
  private var segmentStorage: [DistanceSegment] = []
  private var segmentBaseSeq = 0
  private var lastStatsSample: TelemetrySnapshot?
  private let maxAverageSamples: Int

  private var launchStartedAt: Date?
  private var launchZeroToSixtyKPHRecorded = false
  private var launchZeroToSixtyMPHRecorded = false
  private var launchZeroToOneHundredKPHRecorded = false
  private var launchZeroToOneHundredMPHRecorded = false

  private var window1KM = RollingDistanceWindow(targetMeters: 1_000)
  private var window5KM = RollingDistanceWindow(targetMeters: 5_000)
  private var window10KM = RollingDistanceWindow(targetMeters: 10_000)
  private var window1Mile = RollingDistanceWindow(targetMeters: 1_609.344)
  private var window3Miles = RollingDistanceWindow(targetMeters: 4_828.032)
  private var window5Miles = RollingDistanceWindow(targetMeters: 8_046.72)

  private static let stationaryArmThresholdKPH = 0.5
  private static let maxSampleGapSeconds = 10.0

  init(
    maxStoredSamples: Int = 18_000,
    maxAverageSamples: Int = 36_000,
    maxAverageWindowDistanceMeters: Double = 15_000
  ) {
    _ = maxAverageWindowDistanceMeters
    self.sampleRing = SampleRingBuffer(capacity: max(1, maxStoredSamples))
    self.maxAverageSamples = max(2, maxAverageSamples)
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
    sampleRing.removeAll()
    segmentStorage.removeAll(keepingCapacity: false)
    segmentBaseSeq = 0
    lastStatsSample = nil
    resetLaunchState()
    resetWindows()
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

    sampleRing.append(snapshot)
    stats.sampleCount += 1

    guard statsSnapshot.isUsableFix else {
      lastStatsSample = nil
      return
    }

    if statsSnapshot.speedKPH <= Self.stationaryArmThresholdKPH {
      armLaunch(at: statsSnapshot.timestamp)
    }

    if let lastStatsSample {
      let elapsed = TelemetryMotionEstimator.elapsedSeconds(from: lastStatsSample, to: statsSnapshot)
      if elapsed > 0, elapsed < Self.maxSampleGapSeconds {
        let averageMetersPerSecond = ((lastStatsSample.speedKPH + statsSnapshot.speedKPH) / 2) / 3.6
        let segmentDistance = max(0, averageMetersPerSecond * elapsed)
        if segmentDistance > 0 {
          stats.distanceMeters += segmentDistance
          appendDistanceSegment(distanceMeters: segmentDistance, elapsedSeconds: elapsed)
        }
        updateAccelerationTargets(from: lastStatsSample, to: statsSnapshot, elapsedBetweenSamples: elapsed)
      }
    }

    stats.peakSpeedKPH = max(stats.peakSpeedKPH, statsSnapshot.speedKPH)
    stats.maxLongitudinalG = maxMagnitude(stats.maxLongitudinalG, statsSnapshot.longitudinalG)
    stats.maxLateralG = maxMagnitude(stats.maxLateralG, statsSnapshot.lateralG)
    self.lastStatsSample = statsSnapshot
  }

  private func armLaunch(at timestamp: Date) {
    launchStartedAt = timestamp
    launchZeroToSixtyKPHRecorded = false
    launchZeroToSixtyMPHRecorded = false
    launchZeroToOneHundredKPHRecorded = false
    launchZeroToOneHundredMPHRecorded = false
  }

  private func resetLaunchState() {
    launchStartedAt = nil
    launchZeroToSixtyKPHRecorded = false
    launchZeroToSixtyMPHRecorded = false
    launchZeroToOneHundredKPHRecorded = false
    launchZeroToOneHundredMPHRecorded = false
  }

  private func resetWindows() {
    window1KM.reset()
    window5KM.reset()
    window10KM.reset()
    window1Mile.reset()
    window3Miles.reset()
    window5Miles.reset()
  }

  private func updateAccelerationTargets(
    from previous: TelemetrySnapshot,
    to current: TelemetrySnapshot,
    elapsedBetweenSamples: TimeInterval
  ) {
    guard let launchStartedAt else {
      return
    }

    if !launchZeroToSixtyKPHRecorded,
       let time = crossingTime(
         targetKPH: 60,
         previous: previous,
         current: current,
         elapsedBetweenSamples: elapsedBetweenSamples,
         launchStartedAt: launchStartedAt
       ) {
      launchZeroToSixtyKPHRecorded = true
      stats.zeroToSixtyKPHSeconds = bestDuration(stats.zeroToSixtyKPHSeconds, candidate: time)
    }

    if !launchZeroToSixtyMPHRecorded,
       let time = crossingTime(
         targetKPH: 60 / 0.621371,
         previous: previous,
         current: current,
         elapsedBetweenSamples: elapsedBetweenSamples,
         launchStartedAt: launchStartedAt
       ) {
      launchZeroToSixtyMPHRecorded = true
      stats.zeroToSixtyMPHSeconds = bestDuration(stats.zeroToSixtyMPHSeconds, candidate: time)
    }

    if !launchZeroToOneHundredKPHRecorded,
       let time = crossingTime(
         targetKPH: 100,
         previous: previous,
         current: current,
         elapsedBetweenSamples: elapsedBetweenSamples,
         launchStartedAt: launchStartedAt
       ) {
      launchZeroToOneHundredKPHRecorded = true
      stats.zeroToOneHundredKPHSeconds = bestDuration(stats.zeroToOneHundredKPHSeconds, candidate: time)
    }

    if !launchZeroToOneHundredMPHRecorded,
       let time = crossingTime(
         targetKPH: 100 / 0.621371,
         previous: previous,
         current: current,
         elapsedBetweenSamples: elapsedBetweenSamples,
         launchStartedAt: launchStartedAt
       ) {
      launchZeroToOneHundredMPHRecorded = true
      stats.zeroToOneHundredMPHSeconds = bestDuration(stats.zeroToOneHundredMPHSeconds, candidate: time)
    }
  }

  private func crossingTime(
    targetKPH: Double,
    previous: TelemetrySnapshot,
    current: TelemetrySnapshot,
    elapsedBetweenSamples: TimeInterval,
    launchStartedAt: Date
  ) -> TimeInterval? {
    guard previous.speedKPH < targetKPH, current.speedKPH >= targetKPH else {
      return nil
    }

    let deltaSpeed = current.speedKPH - previous.speedKPH
    guard deltaSpeed > 0 else {
      return nil
    }

    let fraction = (targetKPH - previous.speedKPH) / deltaSpeed
    let crossingDate = previous.timestamp.addingTimeInterval(elapsedBetweenSamples * fraction)
    let duration = crossingDate.timeIntervalSince(launchStartedAt)
    return duration > 0 ? duration : nil
  }

  private func bestDuration(_ current: TimeInterval?, candidate: TimeInterval) -> TimeInterval {
    guard let current else {
      return candidate
    }
    return min(current, candidate)
  }

  private func appendDistanceSegment(distanceMeters: Double, elapsedSeconds: Double) {
    let segment = DistanceSegment(distanceMeters: distanceMeters, elapsedSeconds: elapsedSeconds)
    segmentStorage.append(segment)
    let endSeq = segmentBaseSeq + segmentStorage.count

    stats.averageSpeedLast1KMKPH = window1KM.append(segment, segments: segmentStorage, baseSeq: segmentBaseSeq, endSeq: endSeq)
    stats.averageSpeedLast5KMKPH = window5KM.append(segment, segments: segmentStorage, baseSeq: segmentBaseSeq, endSeq: endSeq)
    stats.averageSpeedLast10KMKPH = window10KM.append(segment, segments: segmentStorage, baseSeq: segmentBaseSeq, endSeq: endSeq)
    stats.averageSpeedLast1MileKPH = window1Mile.append(segment, segments: segmentStorage, baseSeq: segmentBaseSeq, endSeq: endSeq)
    stats.averageSpeedLast3MilesKPH = window3Miles.append(segment, segments: segmentStorage, baseSeq: segmentBaseSeq, endSeq: endSeq)
    stats.averageSpeedLast5MilesKPH = window5Miles.append(segment, segments: segmentStorage, baseSeq: segmentBaseSeq, endSeq: endSeq)

    pruneSegmentStorage()
  }

  private func pruneSegmentStorage() {
    let minTailSeq = min(
      window1KM.tailSeq,
      window5KM.tailSeq,
      window10KM.tailSeq,
      window1Mile.tailSeq,
      window3Miles.tailSeq,
      window5Miles.tailSeq
    )

    let excessPastTail = minTailSeq - segmentBaseSeq
    let excessPastCap = segmentStorage.count - maxAverageSamples
    let dropCount: Int
    if excessPastCap > 0 {
      dropCount = max(excessPastCap, excessPastTail)
    } else if excessPastTail >= 1_024 {
      dropCount = excessPastTail
    } else {
      return
    }

    guard dropCount > 0 else {
      return
    }

    let clampedDrop = min(dropCount, segmentStorage.count)
    segmentStorage.removeFirst(clampedDrop)
    segmentBaseSeq += clampedDrop

    let endSeq = segmentBaseSeq + segmentStorage.count
    window1KM.clampTail(toAtLeast: segmentBaseSeq, segments: segmentStorage, baseSeq: segmentBaseSeq, endSeq: endSeq)
    window5KM.clampTail(toAtLeast: segmentBaseSeq, segments: segmentStorage, baseSeq: segmentBaseSeq, endSeq: endSeq)
    window10KM.clampTail(toAtLeast: segmentBaseSeq, segments: segmentStorage, baseSeq: segmentBaseSeq, endSeq: endSeq)
    window1Mile.clampTail(toAtLeast: segmentBaseSeq, segments: segmentStorage, baseSeq: segmentBaseSeq, endSeq: endSeq)
    window3Miles.clampTail(toAtLeast: segmentBaseSeq, segments: segmentStorage, baseSeq: segmentBaseSeq, endSeq: endSeq)
    window5Miles.clampTail(toAtLeast: segmentBaseSeq, segments: segmentStorage, baseSeq: segmentBaseSeq, endSeq: endSeq)
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

private struct DistanceSegment {
  let distanceMeters: Double
  let elapsedSeconds: Double
}

private struct RollingDistanceWindow {
  let targetMeters: Double
  private(set) var tailSeq = 0
  private var accumulatedDistance = 0.0
  private var accumulatedElapsed = 0.0

  private static let distanceToleranceMeters = 0.01

  init(targetMeters: Double) {
    self.targetMeters = targetMeters
  }

  mutating func reset() {
    tailSeq = 0
    accumulatedDistance = 0
    accumulatedElapsed = 0
  }

  mutating func append(
    _ segment: DistanceSegment,
    segments: [DistanceSegment],
    baseSeq: Int,
    endSeq: Int
  ) -> Double? {
    accumulatedDistance += segment.distanceMeters
    accumulatedElapsed += segment.elapsedSeconds

    while tailSeq < endSeq {
      let oldest = segments[tailSeq - baseSeq]
      if accumulatedDistance - oldest.distanceMeters >= targetMeters {
        accumulatedDistance -= oldest.distanceMeters
        accumulatedElapsed -= oldest.elapsedSeconds
        tailSeq += 1
      } else {
        break
      }
    }

    guard accumulatedDistance + Self.distanceToleranceMeters >= targetMeters, tailSeq < endSeq else {
      return nil
    }

    let oldest = segments[tailSeq - baseSeq]
    let excessDistance = max(0, accumulatedDistance - targetMeters)
    let excessRatio = oldest.distanceMeters > 0 ? min(1, excessDistance / oldest.distanceMeters) : 0
    let effectiveElapsed = accumulatedElapsed - oldest.elapsedSeconds * excessRatio
    guard effectiveElapsed > 0 else {
      return nil
    }

    return targetMeters / effectiveElapsed * 3.6
  }

  mutating func clampTail(
    toAtLeast minSeq: Int,
    segments: [DistanceSegment],
    baseSeq: Int,
    endSeq: Int
  ) {
    guard tailSeq < minSeq else {
      return
    }

    tailSeq = min(minSeq, endSeq)
    accumulatedDistance = 0
    accumulatedElapsed = 0
    for seq in tailSeq..<endSeq {
      let segment = segments[seq - baseSeq]
      accumulatedDistance += segment.distanceMeters
      accumulatedElapsed += segment.elapsedSeconds
    }
  }
}

private struct SampleRingBuffer {
  private var storage: [TelemetrySnapshot?]
  private var head = 0
  private var count = 0
  private let capacity: Int

  init(capacity: Int) {
    self.capacity = capacity
    self.storage = Array(repeating: nil, count: capacity)
  }

  var isEmpty: Bool {
    count == 0
  }

  mutating func append(_ element: TelemetrySnapshot) {
    let writeIndex = (head + count) % capacity
    storage[writeIndex] = element
    if count == capacity {
      head = (head + 1) % capacity
    } else {
      count += 1
    }
  }

  mutating func removeAll() {
    storage = Array(repeating: nil, count: capacity)
    head = 0
    count = 0
  }

  var elements: [TelemetrySnapshot] {
    guard count > 0 else {
      return []
    }

    var result: [TelemetrySnapshot] = []
    result.reserveCapacity(count)
    for offset in 0..<count {
      if let item = storage[(head + offset) % capacity] {
        result.append(item)
      }
    }
    return result
  }
}

struct TelemetrySessionExporter {
  static func csv(samples: [TelemetrySnapshot], redactLocation: Bool = false) -> String {
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

    var lines: [String] = []
    lines.reserveCapacity(samples.count + 1)
    lines.append(header)

    for sample in samples {
      let latitude = redactLocation ? nil : sample.latitude
      let longitude = redactLocation ? nil : sample.longitude
      lines.append([
        DragyDateFormatter.string(from: sample.timestamp),
        sample.speedKPH.csvValue(decimals: 3),
        sample.speedMPH.csvValue(decimals: 3),
        sample.headingDegrees.csvValue(decimals: 3),
        latitude.csvValue(decimals: 7),
        longitude.csvValue(decimals: 7),
        sample.altitudeMeters.csvValue(decimals: 3),
        sample.horizontalAccuracyMeters.csvValue(decimals: 3),
        sample.satelliteCount.map(String.init) ?? "",
        sample.fixQuality.rawValue,
        sample.longitudinalG.csvValue(decimals: 4),
        sample.lateralG.csvValue(decimals: 4),
        sample.verticalG.csvValue(decimals: 4),
        sample.yawRateDegreesPerSecond.csvValue(decimals: 4),
        sample.sourceName.csvEscaped
      ].joined(separator: ","))
    }

    return lines.joined(separator: "\n")
  }
}

enum DragyDateFormatter {
  private static let formatStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

  static func string(from date: Date) -> String {
    date.formatted(formatStyle)
  }
}

private extension Optional where Wrapped == Double {
  func csvValue(decimals: Int) -> String {
    guard let self, self.isFinite else {
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
    var sanitized = self
    if let first = sanitized.first, ["=", "+", "-", "@", "\t", "\r"].contains(first) {
      sanitized = "'\(sanitized)"
    }

    if sanitized.contains(",") || sanitized.contains("\"") || sanitized.contains("\n") || sanitized.contains("\r") {
      return "\"\(sanitized.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    return sanitized
  }
}
