import Foundation

@MainActor
final class MockTelemetryProvider {
  private var task: Task<Void, Never>?

  func start(onUpdate: @escaping (TelemetrySnapshot) -> Void) {
    stop()
    let startedAt = Date()

    task = Task {
      while !Task.isCancelled {
        let elapsed = Date().timeIntervalSince(startedAt)
        let phase = elapsed.truncatingRemainder(dividingBy: 34)
        let speed: Double

        switch phase {
        case 0..<5:
          speed = 0
        case 5..<16:
          let launchProgress = (phase - 5) / 11
          speed = min(136, pow(launchProgress, 0.72) * 136)
        case 16..<24:
          speed = 126 + sin(elapsed * 1.4) * 7
        default:
          let brakingProgress = (phase - 24) / 10
          speed = max(0, 126 * (1 - brakingProgress))
        }

        onUpdate(
          TelemetrySnapshot(
            timestamp: .now,
            speedKPH: speed,
            headingDegrees: 184 + sin(elapsed / 6) * 8,
            latitude: -37.8136 + sin(elapsed / 900) * 0.002,
            longitude: 144.9631 + cos(elapsed / 900) * 0.002,
            altitudeMeters: 48 + sin(elapsed / 10) * 2,
            horizontalAccuracyMeters: 0.8 + abs(sin(elapsed / 5)) * 0.4,
            satelliteCount: 18,
            fixQuality: .threeD,
            longitudinalG: phase < 16 ? 0.22 + sin(elapsed * 1.3) * 0.03 : sin(elapsed * 1.3) * 0.08,
            lateralG: sin(elapsed * 0.9) * 0.08,
            verticalG: 1.0 + sin(elapsed * 2.1) * 0.02,
            yawRateDegreesPerSecond: sin(elapsed * 0.7) * 1.8,
            sourceName: "Mock"
          )
        )

        try? await Task.sleep(for: .milliseconds(150))
      }
    }
  }

  func stop() {
    task?.cancel()
    task = nil
  }
}
