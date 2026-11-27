import Foundation
import Testing
@testable import DragyDash

struct TelemetryRecorderTests {
  @Test func recordsDistancePeakSpeedAndAccelerationTargets() {
    let recorder = TelemetryRecorder()
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    recorder.start(at: start)

    recorder.record(snapshot(at: start, speedKPH: 0))
    recorder.record(snapshot(at: start.addingTimeInterval(5), speedKPH: 100))
    recorder.record(snapshot(at: start.addingTimeInterval(10), speedKPH: 120))
    recorder.record(snapshot(at: start.addingTimeInterval(15), speedKPH: 180))

    #expect(recorder.stats.sampleCount == 4)
    #expect(recorder.stats.peakSpeedKPH == 180)
    #expect(abs(recorder.stats.distanceMeters - 430.56) < 1)
    #expect(abs((recorder.stats.zeroToSixtyKPHSeconds ?? 0) - 3.0) < 0.01)
    #expect(abs((recorder.stats.zeroToSixtyMPHSeconds ?? 0) - 4.83) < 0.05)
    #expect(abs((recorder.stats.zeroToOneHundredKPHSeconds ?? 0) - 5.0) < 0.01)
    #expect(abs((recorder.stats.zeroToOneHundredMPHSeconds ?? 0) - 13.41) < 0.05)
  }

  @Test func exportsSessionCSV() {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let csv = TelemetrySessionExporter.csv(samples: [
      snapshot(at: start, speedKPH: 100, sourceName: "Dragy, Pro")
    ])

    #expect(csv.contains("timestamp,speed_kph,speed_mph"))
    #expect(csv.contains("100.000,62.137"))
    #expect(csv.contains("\"Dragy, Pro\""))
  }

  @Test func keepsRawSamplesWhileUsingDisplaySpeedForStats() {
    let recorder = TelemetryRecorder()
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    recorder.start(at: start)

    recorder.record(
      raw: snapshot(at: start, speedKPH: 3.5),
      statsSnapshot: snapshot(at: start, speedKPH: 0)
    )
    recorder.record(
      raw: snapshot(at: start.addingTimeInterval(1), speedKPH: 4.0),
      statsSnapshot: snapshot(at: start.addingTimeInterval(1), speedKPH: 0)
    )

    #expect(recorder.samples.map(\.speedKPH) == [3.5, 4.0])
    #expect(recorder.stats.peakSpeedKPH == 0)
    #expect(recorder.stats.distanceMeters == 0)
  }

  @Test func calculatesRollingDistanceAverages() {
    let recorder = TelemetryRecorder()
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    recorder.start(at: start)

    for index in 0...72 {
      recorder.record(snapshot(at: start.addingTimeInterval(Double(index) * 5), speedKPH: 100))
    }

    #expect(abs((recorder.stats.averageSpeedLast1KMKPH ?? 0) - 100) < 0.1)
    #expect(abs((recorder.stats.averageSpeedLast5KMKPH ?? 0) - 100) < 0.1)
    #expect(abs((recorder.stats.averageSpeedLast10KMKPH ?? 0) - 100) < 0.1)
    #expect(abs((recorder.stats.averageSpeedLast1MileKPH ?? 0) - 100) < 0.1)
    #expect(abs((recorder.stats.averageSpeedLast3MilesKPH ?? 0) - 100) < 0.1)
    #expect(abs((recorder.stats.averageSpeedLast5MilesKPH ?? 0) - 100) < 0.1)
  }

  @Test func capsStoredSamplesWithoutResettingSampleCount() {
    let recorder = TelemetryRecorder(maxStoredSamples: 3, maxAverageSamples: 10)
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    recorder.start(at: start)

    for index in 0..<5 {
      recorder.record(snapshot(at: start.addingTimeInterval(Double(index)), speedKPH: Double(index)))
    }

    #expect(recorder.stats.sampleCount == 5)
    #expect(recorder.samples.map(\.speedKPH) == [2, 3, 4])
  }

  @Test func ignoresNoFixSamplesForRollingAverages() {
    let recorder = TelemetryRecorder()
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    recorder.start(at: start)

    for index in 0...36 {
      recorder.record(snapshot(at: start.addingTimeInterval(Double(index) * 5), speedKPH: 100))
    }

    let averageBeforeNoFix = recorder.stats.averageSpeedLast1KMKPH
    recorder.record(
      raw: snapshot(at: start.addingTimeInterval(190), speedKPH: 0, fixQuality: .none),
      statsSnapshot: snapshot(at: start.addingTimeInterval(190), speedKPH: 0, fixQuality: .none)
    )

    #expect(abs((averageBeforeNoFix ?? 0) - 100) < 0.1)
    #expect(abs((recorder.stats.averageSpeedLast1KMKPH ?? 0) - 100) < 0.1)
    #expect(recorder.stats.distanceMeters > 4_900)
    #expect(recorder.stats.sampleCount == 38)
  }

  @Test func measuresAccelerationFromLaunchAfterWaitingParked() {
    let recorder = TelemetryRecorder()
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    recorder.start(at: start)

    // Sit stationary for 90 seconds before launching.
    recorder.record(snapshot(at: start, speedKPH: 0))
    recorder.record(snapshot(at: start.addingTimeInterval(90), speedKPH: 0))
    recorder.record(snapshot(at: start.addingTimeInterval(94), speedKPH: 100))

    #expect(abs((recorder.stats.zeroToSixtyKPHSeconds ?? 0) - 2.4) < 0.02)
    #expect(abs((recorder.stats.zeroToOneHundredKPHSeconds ?? 0) - 4.0) < 0.02)

    // Come back to a stop and do a quicker second run; best time should win.
    recorder.record(snapshot(at: start.addingTimeInterval(100), speedKPH: 0))
    recorder.record(snapshot(at: start.addingTimeInterval(103), speedKPH: 100))

    #expect(abs((recorder.stats.zeroToOneHundredKPHSeconds ?? 0) - 3.0) < 0.02)
  }

  @Test func doesNotRecordZeroToSixtyWithoutStationaryLaunch() {
    let recorder = TelemetryRecorder()
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    recorder.start(at: start)

    recorder.record(snapshot(at: start, speedKPH: 40))
    recorder.record(snapshot(at: start.addingTimeInterval(3), speedKPH: 110))

    #expect(recorder.stats.zeroToSixtyKPHSeconds == nil)
    #expect(recorder.stats.zeroToOneHundredKPHSeconds == nil)
  }

  @Test func redactsLocationAndSanitizesFormulaInjectionInCSV() {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let csv = TelemetrySessionExporter.csv(
      samples: [snapshot(at: start, speedKPH: 100, sourceName: "=HYPERLINK(\"https://example.com\")")],
      redactLocation: true
    )

    #expect(!csv.contains("-37.8"))
    #expect(!csv.contains("144.9"))
    #expect(csv.contains("\"'=HYPERLINK(\"\"https://example.com\"\")\""))
  }

  @Test func includesStationaryTimeInRollingAverages() {
    let recorder = TelemetryRecorder()
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    recorder.start(at: start)

    // Drive 1,000 m in 100 s at 36 km/h (10 m/s), then sit stationary for 100 s.
    for second in 0...100 {
      recorder.record(snapshot(at: start.addingTimeInterval(Double(second)), speedKPH: 36))
    }
    #expect(abs((recorder.stats.averageSpeedLast1KMKPH ?? 0) - 36.0) < 0.2)

    for second in 101...200 {
      recorder.record(snapshot(at: start.addingTimeInterval(Double(second)), speedKPH: 0))
    }
    // 1,000 m over ~200 s => ~18 km/h (boundary transition at s=100->101 adds 5 m).
    #expect(abs((recorder.stats.averageSpeedLast1KMKPH ?? 0) - 18.0) < 0.3)
  }

  private func snapshot(
    at date: Date,
    speedKPH: Double,
    fixQuality: FixQuality = .threeD,
    sourceName: String = "Test"
  ) -> TelemetrySnapshot {
    TelemetrySnapshot(
      timestamp: date,
      speedKPH: speedKPH,
      headingDegrees: 90,
      latitude: -37.8,
      longitude: 144.9,
      altitudeMeters: 50,
      horizontalAccuracyMeters: 1,
      satelliteCount: 18,
      fixQuality: fixQuality,
      longitudinalG: 0.2,
      lateralG: 0.01,
      verticalG: 1,
      yawRateDegreesPerSecond: 0,
      sourceName: sourceName
    )
  }
}
