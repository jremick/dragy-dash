import Foundation

enum TelemetrySourceMode: String, CaseIterable, Identifiable {
  case mock = "Mock"
  case bluetooth = "Dragy BLE"

  var id: String { rawValue }
}

enum TelemetryUnitSystem: String, CaseIterable, Identifiable {
  case metric = "Metric"
  case imperial = "Imperial"

  var id: String { rawValue }

  var speedUnitLabel: String {
    switch self {
    case .metric:
      "km/h"
    case .imperial:
      "mph"
    }
  }

  var altitudeUnitLabel: String {
    switch self {
    case .metric:
      "m"
    case .imperial:
      "ft"
    }
  }

  var distanceUnitLabel: String {
    switch self {
    case .metric:
      "km"
    case .imperial:
      "mi"
    }
  }

  func speed(fromKPH speedKPH: Double) -> Double {
    switch self {
    case .metric:
      speedKPH
    case .imperial:
      speedKPH * 0.621371
    }
  }

  func altitude(fromMeters meters: Double) -> Double {
    switch self {
    case .metric:
      meters
    case .imperial:
      meters * 3.28084
    }
  }

  func distance(fromMeters meters: Double) -> Double {
    switch self {
    case .metric:
      meters / 1000
    case .imperial:
      meters / 1609.344
    }
  }
}

enum FixQuality: String {
  case none = "No Fix"
  case twoD = "2D"
  case threeD = "3D"
  case estimated = "Estimated"
}

struct TelemetrySnapshot: Equatable {
  var timestamp: Date
  var speedKPH: Double
  var headingDegrees: Double?
  var latitude: Double? = nil
  var longitude: Double? = nil
  var altitudeMeters: Double?
  var horizontalAccuracyMeters: Double?
  var satelliteCount: Int?
  var fixQuality: FixQuality
  var longitudinalG: Double?
  var lateralG: Double?
  var verticalG: Double?
  var yawRateDegreesPerSecond: Double?
  var sourceName: String

  var speedMPH: Double {
    speedKPH * 0.621371
  }

  var coordinateLabel: String {
    guard let latitude, let longitude else {
      return "--"
    }

    return String(format: "%.5f, %.5f", latitude, longitude)
  }

  static let empty = TelemetrySnapshot(
    timestamp: .now,
    speedKPH: 0,
    headingDegrees: nil,
    altitudeMeters: nil,
    horizontalAccuracyMeters: nil,
    satelliteCount: nil,
    fixQuality: .none,
    longitudinalG: nil,
    lateralG: nil,
    verticalG: nil,
    yawRateDegreesPerSecond: nil,
    sourceName: "Waiting"
  )
}

struct TelemetryRunStats: Equatable {
  var isRecording: Bool
  var startedAt: Date?
  var sampleCount: Int
  var elapsedSeconds: TimeInterval
  var peakSpeedKPH: Double
  var distanceMeters: Double
  var zeroToSixtyKPHSeconds: TimeInterval?
  var zeroToSixtyMPHSeconds: TimeInterval?
  var zeroToOneHundredKPHSeconds: TimeInterval?
  var zeroToOneHundredMPHSeconds: TimeInterval?
  var maxLongitudinalG: Double?
  var maxLateralG: Double?
  var averageSpeedLast1KMKPH: Double?
  var averageSpeedLast5KMKPH: Double?
  var averageSpeedLast10KMKPH: Double?
  var averageSpeedLast1MileKPH: Double?
  var averageSpeedLast3MilesKPH: Double?
  var averageSpeedLast5MilesKPH: Double?

  var peakSpeedMPH: Double {
    peakSpeedKPH * 0.621371
  }

  var distanceMiles: Double {
    distanceMeters / 1609.344
  }

  static let empty = TelemetryRunStats(
    isRecording: false,
    startedAt: nil,
    sampleCount: 0,
    elapsedSeconds: 0,
    peakSpeedKPH: 0,
    distanceMeters: 0,
    zeroToSixtyKPHSeconds: nil,
    zeroToSixtyMPHSeconds: nil,
    zeroToOneHundredKPHSeconds: nil,
    zeroToOneHundredMPHSeconds: nil,
    maxLongitudinalG: nil,
    maxLateralG: nil,
    averageSpeedLast1KMKPH: nil,
    averageSpeedLast5KMKPH: nil,
    averageSpeedLast10KMKPH: nil,
    averageSpeedLast1MileKPH: nil,
    averageSpeedLast3MilesKPH: nil,
    averageSpeedLast5MilesKPH: nil
  )
}
