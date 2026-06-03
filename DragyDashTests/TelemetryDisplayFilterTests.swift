import Foundation
import Testing
@testable import DragyDash

struct TelemetryDisplayFilterTests {
  @Test func zerosStationaryGNSSDriftBelowStartThreshold() {
    var filter = TelemetryDisplayFilter()

    #expect(filter.apply(to: snapshot(speedKPH: 0.08)).speedKPH == 0)
    #expect(filter.apply(to: snapshot(speedKPH: 3.95)).speedKPH == 0)
  }

  @Test func usesHysteresisAfterMotionStarts() {
    var filter = TelemetryDisplayFilter()

    #expect(filter.apply(to: snapshot(speedKPH: 5.0)).speedKPH == 5.0)
    #expect(filter.apply(to: snapshot(speedKPH: 4.0)).speedKPH == 4.0)
    #expect(filter.apply(to: snapshot(speedKPH: 2.1)).speedKPH == 2.1)
    #expect(filter.apply(to: snapshot(speedKPH: 2.0)).speedKPH == 0)
  }

  private func snapshot(speedKPH: Double) -> TelemetrySnapshot {
    TelemetrySnapshot(
      timestamp: Date(timeIntervalSince1970: 1_800_000_000),
      speedKPH: speedKPH,
      headingDegrees: 90,
      latitude: -37.8,
      longitude: 144.9,
      altitudeMeters: 50,
      horizontalAccuracyMeters: 1,
      satelliteCount: 18,
      fixQuality: .threeD,
      longitudinalG: nil,
      lateralG: nil,
      verticalG: nil,
      yawRateDegreesPerSecond: nil,
      sourceName: "Test"
    )
  }
}
