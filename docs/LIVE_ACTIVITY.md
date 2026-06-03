# Live Activity / Dynamic Island

Version: 0.1.0
Last updated: 2026-06-03

DragyDash includes a WidgetKit Live Activity extension for showing live speed outside the app.

## What It Shows

- Compact leading Dynamic Island: live speed number.
- Compact trailing Dynamic Island: unit label.
- Expanded Dynamic Island / Lock Screen: speed, unit, fix quality, battery when known, and DragyDash label.

The setting is available at:

`Settings -> Live Display -> Dynamic Island Speed`

## Implementation

- `DragyDash/LiveActivity/LiveSpeedActivityAttributes.swift` defines the shared ActivityKit attributes and content state.
- `DragyDash/Services/LiveSpeedActivityController.swift` starts, updates, and ends the activity from the app.
- `DragyDashLiveActivityExtension/LiveSpeedActivityWidget.swift` renders the Lock Screen and Dynamic Island presentations.
- `project.yml` embeds the extension and enables:
  - `NSSupportsLiveActivities`
  - `NSSupportsLiveActivitiesFrequentUpdates`
  - `UIBackgroundModes` -> `bluetooth-central`

## Limitations

Live Activities cannot fetch Bluetooth, network, or location data themselves. Apple requires the containing app or ActivityKit push notifications to update the activity content.

For DragyDash, that means:

- The iPhone app must start the Live Activity while it is foregrounded.
- The app updates the activity as Dragy telemetry arrives.
- Continued updates while another app is foregrounded depend on iOS keeping the Bluetooth central session alive in the background.
- If iOS suspends DragyDash, the Dynamic Island value can become stale until the app runs again.

There is no server push path in this prototype.
