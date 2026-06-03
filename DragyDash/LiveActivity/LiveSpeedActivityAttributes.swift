import ActivityKit
import Foundation

struct LiveSpeedActivityAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    var speed: Int
    var unitLabel: String
    var batteryPercent: Int?
    var fixLabel: String
    var updatedAt: Date
  }

  var displayName: String
}
