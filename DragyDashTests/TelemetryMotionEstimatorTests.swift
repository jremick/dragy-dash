import Foundation
import Testing
@testable import DragyDash

struct TelemetryMotionEstimatorTests {
  @Test func derivesLongitudinalGFromSpeedChange() {
    var estimator = TelemetryMotionEstimator()
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    _ = estimator.apply(to: snapshot(at: start, speedKPH: 0, heading: 0))
    let result = estimator.apply(to: snapshot(at: start.addingTimeInterval(2), speedKPH: 36, heading: 0))

    #expect(abs((result.longitudinalG ?? 0) - 0.51) < 0.02)
  }

  @Test func derivesYawRateAndLateralGFromHeadingChange() {
    var estimator = TelemetryMotionEstimator()
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    _ = estimator.apply(to: snapshot(at: start, speedKPH: 36, heading: 0))
    let result = estimator.apply(to: snapshot(at: start.addingTimeInterval(1), speedKPH: 36, heading: 9))

    #expect(abs((result.yawRateDegreesPerSecond ?? 0) - 9) < 0.01)
    #expect(abs((result.lateralG ?? 0) - 0.16) < 0.02)
  }

  @Test func suppressesStationaryHeadingNoise() {
    var estimator = TelemetryMotionEstimator()
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    _ = estimator.apply(to: snapshot(at: start, speedKPH: 0.5, heading: 10))
    let result = estimator.apply(to: snapshot(at: start.addingTimeInterval(1), speedKPH: 0.7, heading: 80))

    #expect(result.longitudinalG == 0)
    #expect(result.lateralG == 0)
    #expect(result.yawRateDegreesPerSecond == 0)
  }

  private func snapshot(at date: Date, speedKPH: Double, heading: Double) -> TelemetrySnapshot {
    TelemetrySnapshot(
      timestamp: date,
      speedKPH: speedKPH,
      headingDegrees: heading,
      latitude: nil,
      longitude: nil,
      altitudeMeters: nil,
      horizontalAccuracyMeters: nil,
      satelliteCount: nil,
      fixQuality: .threeD,
      longitudinalG: nil,
      lateralG: nil,
      verticalG: nil,
      yawRateDegreesPerSecond: nil,
      sourceName: "Test"
    )
  }
}
