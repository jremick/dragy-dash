import ActivityKit
import SwiftUI
import WidgetKit

struct LiveSpeedActivityWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: LiveSpeedActivityAttributes.self) { context in
      LiveSpeedLockScreenView(context: context)
        .activityBackgroundTint(Color.black.opacity(0.88))
        .activitySystemActionForegroundColor(.cyan)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          LiveSpeedValueView(state: context.state, alignment: .leading)
        }

        DynamicIslandExpandedRegion(.trailing) {
          VStack(alignment: .trailing, spacing: 2) {
            Text(context.state.fixLabel)
              .font(.caption2)
              .foregroundStyle(.secondary)
            if let batteryPercent = context.state.batteryPercent {
              Label("\(batteryPercent)%", systemImage: batteryIcon(for: batteryPercent))
                .font(.caption)
            }
          }
        }

        DynamicIslandExpandedRegion(.bottom) {
          HStack {
            Label("DragyDash", systemImage: "gauge.with.dots.needle.67percent")
            Spacer()
            Text(context.state.updatedAt, style: .timer)
              .monospacedDigit()
          }
          .font(.caption)
          .foregroundStyle(.secondary)
        }
      } compactLeading: {
        Text("\(context.state.speed)")
          .font(.system(size: 18, weight: .bold, design: .rounded))
          .monospacedDigit()
          .foregroundStyle(.cyan)
          .minimumScaleFactor(0.6)
          .accessibilityLabel("Speed \(context.state.speed) \(context.state.unitLabel)")
      } compactTrailing: {
        Text(context.state.unitLabel)
          .font(.caption2)
          .fontWeight(.semibold)
          .foregroundStyle(.secondary)
      } minimal: {
        Image(systemName: "gauge.with.dots.needle.67percent")
          .foregroundStyle(.cyan)
      }
      .widgetURL(URL(string: "dragydash://live-speed"))
    }
  }
}

private struct LiveSpeedLockScreenView: View {
  let context: ActivityViewContext<LiveSpeedActivityAttributes>

  var body: some View {
    HStack(spacing: 14) {
      LiveSpeedValueView(state: context.state, alignment: .leading)

      Spacer()

      VStack(alignment: .trailing, spacing: 4) {
        Text(context.attributes.displayName)
          .font(.headline)
        Text(context.state.fixLabel)
          .font(.caption)
          .foregroundStyle(.secondary)
        if let batteryPercent = context.state.batteryPercent {
          Label("\(batteryPercent)%", systemImage: batteryIcon(for: batteryPercent))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
    .padding(.vertical, 6)
  }
}

private struct LiveSpeedValueView: View {
  let state: LiveSpeedActivityAttributes.ContentState
  let alignment: HorizontalAlignment

  var body: some View {
    VStack(alignment: alignment, spacing: 0) {
      Text("\(state.speed)")
        .font(.system(size: 42, weight: .bold, design: .rounded))
        .monospacedDigit()
        .minimumScaleFactor(0.5)
      Text(state.unitLabel)
        .font(.caption)
        .fontWeight(.semibold)
        .foregroundStyle(.secondary)
    }
    .accessibilityElement(children: .combine)
  }
}

private func batteryIcon(for percent: Int) -> String {
  switch percent {
  case 95...100:
    "battery.100percent"
  case 65..<95:
    "battery.75percent"
  case 35..<65:
    "battery.50percent"
  case 10..<35:
    "battery.25percent"
  default:
    "battery.0percent"
  }
}
