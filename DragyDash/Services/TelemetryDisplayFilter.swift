import Foundation

struct TelemetryDisplayFilter {
  var startMovingSpeedKPH = 5.0
  var stopMovingSpeedKPH = 2.0

  private var isMoving = false

  mutating func apply(to snapshot: TelemetrySnapshot) -> TelemetrySnapshot {
    var displaySnapshot = snapshot

    if isMoving {
      if snapshot.speedKPH <= stopMovingSpeedKPH {
        isMoving = false
        displaySnapshot.speedKPH = 0
      }
    } else if snapshot.speedKPH >= startMovingSpeedKPH {
      isMoving = true
    } else {
      displaySnapshot.speedKPH = 0
    }

    return displaySnapshot
  }

  mutating func reset() {
    isMoving = false
  }
}
