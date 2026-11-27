@preconcurrency import ActivityKit
import Foundation

@MainActor
final class LiveSpeedActivityController {
  private var activity: Activity<LiveSpeedActivityAttributes>?
  private var lastUpdate: Date?
  private var pendingTask: Task<Void, Never>?
  private var isStopped = false

  func update(
    telemetry: TelemetrySnapshot,
    unitSystem: TelemetryUnitSystem,
    batteryPercent: Int?
  ) {
    isStopped = false
    guard ActivityAuthorizationInfo().areActivitiesEnabled else {
      return
    }

    let state = LiveSpeedActivityAttributes.ContentState(
      speed: Int(unitSystem.speed(fromKPH: telemetry.speedKPH).rounded()),
      unitLabel: unitSystem.speedUnitLabel,
      batteryPercent: batteryPercent,
      fixLabel: telemetry.fixQuality.rawValue,
      updatedAt: telemetry.timestamp
    )

    let now = Date()
    if let lastUpdate, now.timeIntervalSince(lastUpdate) < 1 {
      return
    }
    lastUpdate = now

    pendingTask?.cancel()
    pendingTask = Task { [weak self] in
      guard let self, !Task.isCancelled, !self.isStopped else {
        return
      }

      if let activity = self.currentActivity() {
        await activity.update(ActivityContent(state: state, staleDate: now.addingTimeInterval(8)))
      } else {
        do {
          self.activity = try Activity<LiveSpeedActivityAttributes>.request(
            attributes: LiveSpeedActivityAttributes(displayName: "DragyDash"),
            content: ActivityContent(state: state, staleDate: now.addingTimeInterval(8)),
            pushType: nil
          )
        } catch {
          self.activity = nil
        }
      }
    }
  }

  func end() {
    isStopped = true
    pendingTask?.cancel()
    pendingTask = Task { [weak self] in
      for activity in Activity<LiveSpeedActivityAttributes>.activities {
        await activity.end(nil, dismissalPolicy: .immediate)
      }
      self?.activity = nil
      self?.lastUpdate = nil
    }
  }

  private func currentActivity() -> Activity<LiveSpeedActivityAttributes>? {
    if let activity, Activity<LiveSpeedActivityAttributes>.activities.contains(where: { $0.id == activity.id }) {
      return activity
    }

    activity = Activity<LiveSpeedActivityAttributes>.activities.first
    return activity
  }
}
