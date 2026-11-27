import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct DashboardView: View {
  var store: TelemetryStore
  @Environment(\.verticalSizeClass) private var verticalSizeClass
  @State private var isShowingSettings = false
  @State private var isConfirmingReset = false

  var body: some View {
    Group {
      if verticalSizeClass == .compact {
        landscapeLayout
      } else {
        portraitLayout
      }
    }
    .background(Color(.systemGroupedBackground))
    .safeAreaInset(edge: .bottom, spacing: 0) {
      VStack(spacing: 0) {
        Divider()
        bottomBar
          .padding(.horizontal, 16)
          .padding(.vertical, 6)
          .background(Color(.systemGroupedBackground))
      }
    }
    .sheet(isPresented: $isShowingSettings) {
      SettingsView(store: store)
    }
    .confirmationDialog(
      "Reset Session?",
      isPresented: $isConfirmingReset,
      titleVisibility: .visible
    ) {
      Button(
        store.sessionSavingEnabled ? "Save & Reset" : "Reset Session",
        role: .destructive,
        action: store.resetRecording
      )
      Button("Cancel", role: .cancel) {}
    } message: {
      if store.sessionSavingEnabled {
        Text("The current session will be saved to CSV before clearing peak speed, distance, averages, and acceleration times.")
      } else {
        Text("This clears peak speed, distance, averages, and acceleration times.")
      }
    }
    .onAppear {
      setIdleTimerDisabled(true)
    }
    .onDisappear {
      setIdleTimerDisabled(false)
    }
  }

  private var portraitLayout: some View {
    ScrollView {
      VStack(spacing: 18) {
        SpeedometerView(
          telemetry: store.displayTelemetry,
          unitSystem: store.unitSystem,
          statusSummary: dashboardStatus
        )

        SpeedAveragesView(
          stats: store.runStats,
          unitSystem: store.unitSystem
        )

        SensorSummaryView(
          telemetry: store.displayTelemetry,
          unitSystem: store.unitSystem
        )

        RunStatsView(store: store)
      }
      .padding(16)
      .padding(.bottom, 72)
    }
  }

  private var landscapeLayout: some View {
    HStack(alignment: .top, spacing: 14) {
      SpeedometerView(
        telemetry: store.displayTelemetry,
        unitSystem: store.unitSystem,
        statusSummary: dashboardStatus
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)

      ScrollView {
        VStack(spacing: 12) {
          SpeedAveragesView(
            stats: store.runStats,
            unitSystem: store.unitSystem
          )

          SensorSummaryView(
            telemetry: store.displayTelemetry,
            unitSystem: store.unitSystem
          )

          RunStatsView(store: store)
        }
        .padding(.bottom, 64)
      }
      .frame(maxWidth: .infinity)
    }
    .padding(.horizontal, 16)
    .padding(.top, 10)
  }

  private var dashboardStatus: DashboardStatusSummary {
    if store.sourceMode == .mock {
      return DashboardStatusSummary(label: "Demo · \(store.displayTelemetry.fixQuality.rawValue)", color: .blue)
    }

    if store.connectedDeviceName == nil {
      switch store.bluetoothStatus {
      case .scanning, .connecting:
        return DashboardStatusSummary(label: store.bluetoothStatus.label, color: .orange)
      case .unauthorized, .poweredOff, .unsupported, .failed:
        return DashboardStatusSummary(label: store.bluetoothStatus.label, color: .red)
      default:
        return DashboardStatusSummary(label: "Disconnected", color: .red)
      }
    }

    if store.isTelemetryStale {
      return DashboardStatusSummary(label: "Stream Stale", color: .orange)
    }

    guard store.displayTelemetry.isUsableFix else {
      return DashboardStatusSummary(label: "Waiting for GPS Fix", color: .orange)
    }

    let satLabel = store.displayTelemetry.satelliteCount.map { " · \($0) sats" } ?? ""
    switch store.displayTelemetry.gpsQuality {
    case .good:
      return DashboardStatusSummary(label: "\(store.displayTelemetry.fixQuality.rawValue)\(satLabel)", color: .green)
    case .fair:
      return DashboardStatusSummary(label: "\(store.displayTelemetry.fixQuality.rawValue)\(satLabel)", color: .yellow)
    case .poor:
      return DashboardStatusSummary(label: "Weak GPS\(satLabel)", color: .orange)
    case .none:
      return DashboardStatusSummary(label: "No GPS Fix", color: .red)
    }
  }

  private var bottomBar: some View {
    HStack(spacing: 10) {
      Text("DragyDash")
        .font(.headline)
        .fontWeight(.semibold)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)

      BatteryStatusView(percent: store.batteryPercent)

      Spacer(minLength: 8)

      BottomBarButton(
        systemImage: "arrow.counterclockwise",
        accessibilityLabel: "Reset session",
        action: { isConfirmingReset = true }
      )

      BottomBarButton(
        systemImage: "gearshape.fill",
        accessibilityLabel: "Settings",
        action: { isShowingSettings = true }
      )
    }
    .frame(height: 56)
  }
}

private struct DashboardStatusSummary {
  let label: String
  let color: Color
}

private struct BottomBarButton: View {
  let systemImage: String
  let accessibilityLabel: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.title2)
        .fontWeight(.semibold)
        .foregroundStyle(.blue)
        .frame(width: 52, height: 52)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(accessibilityLabel)
  }
}

private struct SpeedometerView: View {
  let telemetry: TelemetrySnapshot
  let unitSystem: TelemetryUnitSystem
  let statusSummary: DashboardStatusSummary

  var body: some View {
    VStack(alignment: .center, spacing: 8) {
      HStack(spacing: 6) {
        Circle()
          .fill(statusSummary.color)
          .frame(width: 8, height: 8)
        Text(statusSummary.label)
          .font(.caption)
          .fontWeight(.semibold)
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 4)
      .background(Color(.secondarySystemGroupedBackground))
      .clipShape(Capsule())
      .accessibilityElement(children: .combine)

      liveSpeed
    }
    .frame(maxWidth: .infinity)
    .padding(16)
    .background(.background)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private var liveSpeed: some View {
    VStack(alignment: .center, spacing: 0) {
      Text(String(format: "%.0f", unitSystem.speed(fromKPH: telemetry.speedKPH)))
        .font(.system(size: 118, weight: .semibold, design: .rounded))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .frame(maxWidth: .infinity, alignment: .center)

      Text(unitSystem.speedUnitLabel)
        .font(.title3)
        .fontWeight(.semibold)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .center)
    }
  }
}

private struct SensorSummaryView: View {
  let telemetry: TelemetrySnapshot
  let unitSystem: TelemetryUnitSystem

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 0) {
      TelemetryInlineStat(
        title: "Satellites",
        systemImage: "antenna.radiowaves.left.and.right",
        value: telemetry.satelliteCount.map(String.init) ?? "--"
      )
      .frame(maxWidth: .infinity)

      TelemetryInlineStat(
        title: "Accuracy",
        systemImage: "scope",
        value: measurement(telemetry.horizontalAccuracyMeters, decimals: 1)
      )
      .frame(maxWidth: .infinity)

      TelemetryInlineStat(
        title: "Altitude",
        systemImage: "mountain.2",
        value: measurement(telemetry.altitudeMeters, decimals: 0)
      )
      .frame(maxWidth: .infinity)
    }
    .padding(.vertical, 14)
    .padding(.horizontal, 12)
    .frame(maxWidth: .infinity)
    .background(.background)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private func measurement(_ value: Double?, decimals: Int) -> String {
    guard let value else {
      return "--"
    }
    return String(
      format: "%.\(decimals)f %@",
      unitSystem.altitude(fromMeters: value),
      unitSystem.altitudeUnitLabel
    )
  }
}

private struct TelemetryInlineStat: View {
  let title: String
  let systemImage: String
  let value: String

  var body: some View {
    VStack(alignment: .center, spacing: 3) {
      Image(systemName: systemImage)
        .font(.title2)
        .fontWeight(.semibold)
        .foregroundStyle(.blue)
        .frame(height: 24)

      Text(title)
        .font(.caption2)
        .fontWeight(.semibold)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.7)

      Text(value)
        .font(.title3)
        .fontWeight(.semibold)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }
    .multilineTextAlignment(.center)
  }
}

private struct BatteryStatusView: View {
  let percent: Int?

  var body: some View {
    HStack(spacing: 5) {
      Image(systemName: batteryIcon(for: percent ?? 0))
        .imageScale(.large)
      Text(percent.map { "\($0)%" } ?? "--")
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
    .font(.headline)
    .foregroundStyle(.secondary)
    .frame(minWidth: 58, maxWidth: 72, minHeight: 52, alignment: .leading)
    .accessibilityLabel(percent.map { "Battery \($0) percent" } ?? "Battery unknown")
  }
}

private struct SpeedAveragesView: View {
  let stats: TelemetryRunStats
  let unitSystem: TelemetryUnitSystem

  var body: some View {
    HStack(alignment: .center, spacing: 0) {
      AverageSpeedTile(
        title: firstWindowTitle,
        speedKPH: firstWindowSpeedKPH,
        unitSystem: unitSystem
      )
      .frame(maxWidth: .infinity)

      Divider()
        .frame(height: 58)

      AverageSpeedTile(
        title: secondWindowTitle,
        speedKPH: secondWindowSpeedKPH,
        unitSystem: unitSystem
      )
      .frame(maxWidth: .infinity)

      Divider()
        .frame(height: 58)

      AverageSpeedTile(
        title: thirdWindowTitle,
        speedKPH: thirdWindowSpeedKPH,
        unitSystem: unitSystem
      )
      .frame(maxWidth: .infinity)
    }
    .padding(.vertical, 14)
    .padding(.horizontal, 12)
    .frame(maxWidth: .infinity)
    .background(.background)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private var firstWindowTitle: String {
    switch unitSystem {
    case .metric:
      "1 km"
    case .imperial:
      "1 mi"
    }
  }

  private var secondWindowTitle: String {
    switch unitSystem {
    case .metric:
      "5 km"
    case .imperial:
      "3 mi"
    }
  }

  private var thirdWindowTitle: String {
    switch unitSystem {
    case .metric:
      "10 km"
    case .imperial:
      "5 mi"
    }
  }

  private var firstWindowSpeedKPH: Double? {
    switch unitSystem {
    case .metric:
      stats.averageSpeedLast1KMKPH
    case .imperial:
      stats.averageSpeedLast1MileKPH
    }
  }

  private var secondWindowSpeedKPH: Double? {
    switch unitSystem {
    case .metric:
      stats.averageSpeedLast5KMKPH
    case .imperial:
      stats.averageSpeedLast3MilesKPH
    }
  }

  private var thirdWindowSpeedKPH: Double? {
    switch unitSystem {
    case .metric:
      stats.averageSpeedLast10KMKPH
    case .imperial:
      stats.averageSpeedLast5MilesKPH
    }
  }
}

private struct AverageSpeedTile: View {
  let title: String
  let speedKPH: Double?
  let unitSystem: TelemetryUnitSystem

  var body: some View {
    VStack(alignment: .center, spacing: 3) {
      Text(title)
        .font(.caption2)
        .fontWeight(.semibold)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)

      HStack(alignment: .firstTextBaseline, spacing: 4) {
        Text(formattedSpeed)
          .font(.system(size: 36, weight: .semibold, design: .rounded))
          .monospacedDigit()
          .lineLimit(1)
          .minimumScaleFactor(0.55)

        Text(unitSystem.speedUnitLabel)
          .font(.caption)
          .fontWeight(.semibold)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .minimumScaleFactor(0.75)
      }
    }
    .multilineTextAlignment(.center)
  }

  private var formattedSpeed: String {
    guard let speedKPH else {
      return "--"
    }

    return String(format: "%.0f", unitSystem.speed(fromKPH: speedKPH))
  }
}

private struct SettingsView: View {
  var store: TelemetryStore
  @Environment(\.dismiss) private var dismiss
  @State private var copiedDiagnostics = false

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 14) {
          SettingsSection(title: "Units", systemImage: "ruler") {
            Picker("Units", selection: Binding(
              get: { store.unitSystem },
              set: { store.setUnitSystem($0) }
            )) {
              ForEach(TelemetryUnitSystem.allCases) { unitSystem in
                Text(unitSystem.rawValue).tag(unitSystem)
              }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("unitSystemPicker")
          }

          SettingsSection(title: "Telemetry Source", systemImage: "waveform.path.ecg") {
            Picker("Telemetry Source", selection: Binding(
              get: { store.sourceMode },
              set: { store.setSourceMode($0) }
            )) {
              ForEach(TelemetrySourceMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
              }
            }
            .pickerStyle(.segmented)
          }

          SettingsSection(title: "Sessions", systemImage: "folder") {
            VStack(alignment: .leading, spacing: 12) {
              Toggle(isOn: Binding(
                get: { store.sessionSavingEnabled },
                set: { store.setSessionSavingEnabled($0) }
              )) {
                Label("Save Sessions", systemImage: "tray.and.arrow.down")
              }

              Toggle(isOn: Binding(
                get: { store.redactExportLocation },
                set: { store.setRedactExportLocation($0) }
              )) {
                Label("Omit GPS Coordinates in CSV", systemImage: "location.slash")
              }

              HStack {
                Button {
                  store.saveCurrentSession()
                } label: {
                  Label("Save Current", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!store.sessionSavingEnabled || store.runStats.sampleCount == 0)

                Button(role: .destructive) {
                  store.clearSavedSessions()
                } label: {
                  Label("Clear", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .disabled(store.savedSessions.isEmpty)
              }

              if let error = store.lastSaveError {
                Text(error)
                  .font(.caption)
                  .foregroundStyle(.red)
              }

              if store.savedSessions.isEmpty {
                Text("No saved sessions")
                  .font(.subheadline)
                  .foregroundStyle(.secondary)
              } else {
                VStack(spacing: 8) {
                  ForEach(store.savedSessions) { session in
                    SavedSessionRow(session: session)
                  }
                }
              }
            }
          }

          SettingsSection(title: "Live Display", systemImage: "livephoto") {
            Toggle(isOn: Binding(
              get: { store.liveActivityEnabled },
              set: { store.setLiveActivityEnabled($0) }
            )) {
              Label("Dynamic Island Speed", systemImage: "platter.filled.top.iphone")
            }
          }

          SettingsSection(title: "Dragy", systemImage: "antenna.radiowaves.left.and.right") {
            VStack(alignment: .leading, spacing: 10) {
              Text(connectionLabel)
                .font(.headline)

              if let connectedDeviceID = store.connectedDeviceID {
                Text(connectedDeviceID)
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .monospaced()
                  .textSelection(.enabled)
              }

              HStack {
                Button {
                  store.scanForDragy()
                } label: {
                  Label("Scan", systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderedProminent)

                if store.connectedDeviceName != nil {
                  Button(role: .destructive) {
                    store.disconnectDragy()
                  } label: {
                    Label("Disconnect", systemImage: "xmark.circle")
                  }
                  .buttonStyle(.bordered)
                } else {
                  Button {
                    store.stopScanning()
                  } label: {
                    Label("Stop", systemImage: "stop.circle")
                  }
                  .buttonStyle(.bordered)
                }

                Button {
                  copyToPasteboard(store.diagnosticReport(redacted: true))
                  copiedDiagnostics = true
                  Task {
                    try? await Task.sleep(for: .seconds(2))
                    copiedDiagnostics = false
                  }
                } label: {
                  Label(
                    copiedDiagnostics ? "Copied" : "Copy Log",
                    systemImage: copiedDiagnostics ? "checkmark" : "doc.on.doc"
                  )
                }
                .buttonStyle(.bordered)
              }

              Text("Copied diagnostic logs redact GPS coordinates, GNSS payloads, and device IDs.")
                .font(.caption)
                .foregroundStyle(.secondary)

              if !store.discoveredDragyDevices.isEmpty {
                Divider()
                Text("Discovered Devices")
                  .font(.caption)
                  .fontWeight(.semibold)
                  .foregroundStyle(.secondary)

                VStack(spacing: 6) {
                  ForEach(store.discoveredDragyDevices) { device in
                    HStack {
                      VStack(alignment: .leading, spacing: 2) {
                        Text(device.name)
                          .font(.subheadline)
                          .fontWeight(.medium)
                        Text("RSSI \(device.rssi) dBm")
                          .font(.caption2)
                          .foregroundStyle(.secondary)
                      }
                      Spacer()
                      if store.connectedDeviceID == device.id.uuidString {
                        Text("Connected")
                          .font(.caption)
                          .foregroundStyle(.green)
                      } else {
                        Button("Connect") {
                          store.connect(to: device)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                      }
                    }
                    .padding(8)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                  }
                }
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
        .padding(16)
      }
      .background(Color(.systemGroupedBackground))
      .navigationTitle("Settings")
      .toolbarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") {
            dismiss()
          }
        }
      }
    }
  }

  private var connectionLabel: String {
    if let deviceName = store.connectedDeviceName {
      return "Connected to \(deviceName)"
    }

    return store.bluetoothStatus.label
  }
}

private struct SettingsSection<Content: View>: View {
  let title: String
  let systemImage: String
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label(title, systemImage: systemImage)
        .font(.headline)
      content
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.background)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct SavedSessionRow: View {
  let session: SavedTelemetrySession

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: "doc.text")
        .foregroundStyle(.blue)
        .frame(width: 24)

      VStack(alignment: .leading, spacing: 3) {
        Text(session.createdAt.formatted(date: .abbreviated, time: .shortened))
          .font(.subheadline)
          .fontWeight(.semibold)
        Text(ByteCountFormatter.string(fromByteCount: Int64(session.byteCount), countStyle: .file))
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()

      ShareLink(item: session.url) {
        Label("Export", systemImage: "square.and.arrow.up")
      }
      .buttonStyle(.bordered)
    }
    .padding(10)
    .background(Color(.secondarySystemGroupedBackground))
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct RunStatsView: View {
  var store: TelemetryStore

  private let columns = [
    GridItem(.flexible(), spacing: 10),
    GridItem(.flexible(), spacing: 10)
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      LazyVGrid(columns: columns, spacing: 10) {
        CompactStat(title: zeroToSixtyTitle, value: optionalDuration(zeroToSixtySeconds), icon: "bolt")
        CompactStat(title: zeroToOneHundredTitle, value: optionalDuration(zeroToOneHundredSeconds), icon: "bolt.fill")
        CompactStat(title: "Peak", value: speed(store.runStats.peakSpeedKPH), icon: "gauge.with.dots.needle.67percent")
        CompactStat(title: "Distance", value: distance(store.runStats.distanceMeters), icon: "point.topleft.down.curvedto.point.bottomright.up")
        CompactStat(title: "Lateral", value: gForce(store.telemetry.lateralG), icon: "arrow.left.and.right")
        CompactStat(title: "Longitudinal", value: gForce(store.telemetry.longitudinalG), icon: "arrow.up.and.down")
      }
    }
    .padding(14)
    .background(.background)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private func optionalDuration(_ seconds: TimeInterval?) -> String {
    guard let seconds else {
      return "--"
    }

    return String(format: "%.2f s", seconds)
  }

  private var zeroToSixtyTitle: String {
    switch store.unitSystem {
    case .metric:
      "0-60 km/h"
    case .imperial:
      "0-60 mph"
    }
  }

  private var zeroToOneHundredTitle: String {
    switch store.unitSystem {
    case .metric:
      "0-100 km/h"
    case .imperial:
      "0-100 mph"
    }
  }

  private var zeroToSixtySeconds: TimeInterval? {
    switch store.unitSystem {
    case .metric:
      store.runStats.zeroToSixtyKPHSeconds
    case .imperial:
      store.runStats.zeroToSixtyMPHSeconds
    }
  }

  private var zeroToOneHundredSeconds: TimeInterval? {
    switch store.unitSystem {
    case .metric:
      store.runStats.zeroToOneHundredKPHSeconds
    case .imperial:
      store.runStats.zeroToOneHundredMPHSeconds
    }
  }

  private func speed(_ speedKPH: Double) -> String {
    String(
      format: "%.0f %@",
      store.unitSystem.speed(fromKPH: speedKPH),
      store.unitSystem.speedUnitLabel
    )
  }

  private func distance(_ meters: Double) -> String {
    String(
      format: "%.2f %@",
      store.unitSystem.distance(fromMeters: meters),
      store.unitSystem.distanceUnitLabel
    )
  }

  private func gForce(_ value: Double?) -> String {
    guard let value else {
      return "--"
    }

    return String(format: "%.2f g", value)
  }
}

private struct CompactStat: View {
  let title: String
  let value: String
  let icon: String

  var body: some View {
    HStack(spacing: 9) {
      Image(systemName: icon)
        .font(.title2)
        .fontWeight(.semibold)
        .foregroundStyle(.blue)
        .frame(width: 30)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.caption)
          .foregroundStyle(.secondary)
        Text(value)
          .font(.title3)
          .fontWeight(.semibold)
          .monospacedDigit()
          .lineLimit(1)
          .minimumScaleFactor(0.75)
      }

      Spacer(minLength: 0)
    }
    .frame(minHeight: 48)
  }
}

@MainActor
private func copyToPasteboard(_ value: String) {
  #if canImport(UIKit)
  UIPasteboard.general.string = value
  #endif
}

@MainActor
private func setIdleTimerDisabled(_ disabled: Bool) {
  #if canImport(UIKit)
  UIApplication.shared.isIdleTimerDisabled = disabled
  #endif
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

#Preview {
  DashboardView(store: TelemetryStore.preview)
}
