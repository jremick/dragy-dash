import Foundation
import Observation

@MainActor
@Observable
final class TelemetryStore {
  var sourceMode: TelemetrySourceMode = .mock
  var telemetry: TelemetrySnapshot = .empty
  var displayTelemetry: TelemetrySnapshot = .empty
  var runStats = TelemetryRunStats.empty
  var bluetoothStatus: BluetoothStatus = .unknown
  var diagnostics = BLEDiagnostics()
  var unitSystem: TelemetryUnitSystem = .metric
  var batteryPercent: Int?
  var connectedDeviceName: String?
  var connectedDeviceID: String?
  var sessionSavingEnabled = true
  var redactExportLocation = false
  var savedSessions: [SavedTelemetrySession] = []
  var liveActivityEnabled = true
  var isTelemetryStale = false
  var lastSaveError: String?

  var discoveredDragyDevices: [BLEDevice] {
    diagnostics.devices.filter(\.isDragyCandidate)
  }

  @ObservationIgnored private let mockProvider = MockTelemetryProvider()
  @ObservationIgnored private let bluetoothService = DragyBluetoothService()
  @ObservationIgnored private let recorder = TelemetryRecorder()
  @ObservationIgnored private let savedSessionStore = SavedSessionStore()
  @ObservationIgnored private let liveSpeedActivityController = LiveSpeedActivityController()
  @ObservationIgnored private var displayFilter = TelemetryDisplayFilter()
  @ObservationIgnored private var motionEstimator = TelemetryMotionEstimator()
  @ObservationIgnored private var lastTelemetryAt: Date?
  @ObservationIgnored private var stalenessTask: Task<Void, Never>?

  @ObservationIgnored private let unitSystemDefaultsKey = "dragyDash.unitSystem"
  @ObservationIgnored private let liveActivityDefaultsKey = "dragyDash.liveActivityEnabled"
  @ObservationIgnored private let redactLocationDefaultsKey = "dragyDash.redactExportLocation"
  @ObservationIgnored private static let telemetryStaleInterval: TimeInterval = 4.0

  init() {
    sessionSavingEnabled = savedSessionStore.isSavingEnabled
    savedSessions = savedSessionStore.loadSessions()
    if let storedUnits = UserDefaults.standard.string(forKey: unitSystemDefaultsKey),
       let parsed = TelemetryUnitSystem(rawValue: storedUnits) {
      unitSystem = parsed
    }
    if UserDefaults.standard.object(forKey: liveActivityDefaultsKey) != nil {
      liveActivityEnabled = UserDefaults.standard.bool(forKey: liveActivityDefaultsKey)
    }
    if UserDefaults.standard.object(forKey: redactLocationDefaultsKey) != nil {
      redactExportLocation = UserDefaults.standard.bool(forKey: redactLocationDefaultsKey)
    }

    bluetoothService.onStatusChanged = { [weak self] status in
      self?.bluetoothStatus = status
    }
    bluetoothService.onDiagnosticsChanged = { [weak self] diagnostics in
      self?.diagnostics = diagnostics
    }
    bluetoothService.onTelemetry = { [weak self] telemetry in
      self?.handleTelemetry(telemetry)
    }
    bluetoothService.onBatteryLevelChanged = { [weak self] batteryPercent in
      self?.batteryPercent = batteryPercent
      self?.updateLiveActivity()
    }
    bluetoothService.onConnectedDeviceChanged = { [weak self] name, id in
      self?.connectedDeviceName = name
      self?.connectedDeviceID = id
    }
    bluetoothService.onDisconnected = { [weak self] in
      self?.handleBluetoothDisconnect()
    }

    recorder.start()
    runStats = recorder.stats
    startStalenessMonitor()
  }

  func setUnitSystem(_ unitSystem: TelemetryUnitSystem) {
    self.unitSystem = unitSystem
    UserDefaults.standard.set(unitSystem.rawValue, forKey: unitSystemDefaultsKey)
    updateLiveActivity()
  }

  func setSourceMode(_ mode: TelemetrySourceMode) {
    sourceMode = mode
    resetDisplayTelemetry()

    switch mode {
    case .mock:
      bluetoothService.disconnect()
      batteryPercent = 84
      startMockTelemetry()
    case .bluetooth:
      mockProvider.stop()
      batteryPercent = nil
      bluetoothService.startScan()
    }
  }

  func startMockTelemetry() {
    guard sourceMode == .mock else {
      return
    }

    batteryPercent = batteryPercent ?? 84
    mockProvider.start { [weak self] telemetry in
      self?.handleTelemetry(telemetry)
    }
  }

  func scanForDragy(includeAllDevices: Bool = false) {
    sourceMode = .bluetooth
    resetDisplayTelemetry()
    mockProvider.stop()
    bluetoothService.startScan(includeAllDevices: includeAllDevices)
  }

  func stopScanning() {
    bluetoothService.stopScan()
  }

  func disconnectDragy() {
    bluetoothService.disconnect()
  }

  func connect(to device: BLEDevice) {
    sourceMode = .bluetooth
    resetDisplayTelemetry()
    mockProvider.stop()
    bluetoothService.connect(to: device)
  }

  func resetRecording() {
    saveCurrentSession()
    recorder.reset(startRecording: runStats.isRecording)
    displayFilter.reset()
    motionEstimator.reset()
    runStats = recorder.stats
  }

  func sessionCSV(redactLocation: Bool? = nil) -> String {
    TelemetrySessionExporter.csv(
      samples: recorder.samples,
      redactLocation: redactLocation ?? redactExportLocation
    )
  }

  func setSessionSavingEnabled(_ enabled: Bool) {
    savedSessionStore.setSavingEnabled(enabled)
    sessionSavingEnabled = enabled
  }

  func setRedactExportLocation(_ enabled: Bool) {
    UserDefaults.standard.set(enabled, forKey: redactLocationDefaultsKey)
    redactExportLocation = enabled
  }

  func setLiveActivityEnabled(_ enabled: Bool) {
    UserDefaults.standard.set(enabled, forKey: liveActivityDefaultsKey)
    liveActivityEnabled = enabled
    if enabled {
      updateLiveActivity()
    } else {
      liveSpeedActivityController.end()
    }
  }

  func saveCurrentSession() {
    guard sessionSavingEnabled, recorder.hasSamples else {
      return
    }

    do {
      savedSessions = try savedSessionStore.save(csv: sessionCSV())
      lastSaveError = nil
    } catch {
      lastSaveError = error.localizedDescription
      savedSessions = savedSessionStore.loadSessions()
    }
  }

  func clearSavedSessions() {
    do {
      try savedSessionStore.clear()
      lastSaveError = nil
    } catch {
      lastSaveError = error.localizedDescription
    }
    savedSessions = savedSessionStore.loadSessions()
  }

  func diagnosticReport(redacted: Bool = true) -> String {
    BLEDiagnosticReport.make(
      status: bluetoothStatus,
      diagnostics: diagnostics,
      telemetry: telemetry,
      batteryPercent: batteryPercent,
      redacted: redacted
    )
  }

  private func handleTelemetry(_ telemetry: TelemetrySnapshot) {
    let enrichedTelemetry = motionEstimator.apply(to: telemetry)
    let displayTelemetry = displayFilter.apply(to: enrichedTelemetry)

    self.telemetry = enrichedTelemetry
    self.displayTelemetry = displayTelemetry
    lastTelemetryAt = Date()
    isTelemetryStale = false
    recorder.record(raw: telemetry, statsSnapshot: displayTelemetry)
    runStats = recorder.stats
    updateLiveActivity()
  }

  private func handleBluetoothDisconnect() {
    batteryPercent = nil
    resetDisplayTelemetry()
    if liveActivityEnabled {
      liveSpeedActivityController.end()
    }
  }

  private func resetDisplayTelemetry() {
    displayFilter.reset()
    motionEstimator.reset()
    telemetry = .empty
    displayTelemetry = .empty
    lastTelemetryAt = nil
    isTelemetryStale = false
  }

  private func startStalenessMonitor() {
    stalenessTask?.cancel()
    stalenessTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(1))
        guard let self, !Task.isCancelled else {
          return
        }

        if let lastTelemetryAt = self.lastTelemetryAt,
           Date().timeIntervalSince(lastTelemetryAt) > Self.telemetryStaleInterval {
          if !self.isTelemetryStale {
            self.isTelemetryStale = true
            self.displayFilter.reset()
            self.displayTelemetry.speedKPH = 0
            self.updateLiveActivity()
          }
        }
      }
    }
  }

  private func updateLiveActivity() {
    guard liveActivityEnabled else {
      return
    }

    guard lastTelemetryAt != nil else {
      return
    }

    liveSpeedActivityController.update(
      telemetry: displayTelemetry,
      unitSystem: unitSystem,
      batteryPercent: batteryPercent
    )
  }

  static var preview: TelemetryStore {
    let store = TelemetryStore()
    let now = Date()
    store.telemetry = TelemetrySnapshot(
      timestamp: now,
      speedKPH: 112,
      headingDegrees: 186,
      latitude: -37.8136,
      longitude: 144.9631,
      altitudeMeters: 51,
      horizontalAccuracyMeters: 0.9,
      satelliteCount: 18,
      fixQuality: .threeD,
      longitudinalG: 0.12,
      lateralG: -0.04,
      verticalG: 1.01,
      yawRateDegreesPerSecond: 1.4,
      sourceName: "Preview"
    )
    store.displayTelemetry = store.telemetry
    store.lastTelemetryAt = now
    store.bluetoothStatus = .connected("Dragy Pro")
    store.batteryPercent = 84
    store.connectedDeviceName = "Dragy Pro"
    store.connectedDeviceID = "PREVIEW-DRAGY-ID"
    store.sessionSavingEnabled = true
    store.liveActivityEnabled = true
    store.savedSessions = [
      SavedTelemetrySession(
        url: URL(fileURLWithPath: "/tmp/dragydash-session-preview.csv"),
        createdAt: now.addingTimeInterval(-120),
        byteCount: 12_480
      )
    ]
    store.runStats = TelemetryRunStats(
      isRecording: true,
      startedAt: now.addingTimeInterval(-12),
      sampleCount: 60,
      elapsedSeconds: 12,
      peakSpeedKPH: 118,
      distanceMeters: 252,
      zeroToSixtyKPHSeconds: 5.1,
      zeroToSixtyMPHSeconds: 8.4,
      zeroToOneHundredKPHSeconds: 9.1,
      zeroToOneHundredMPHSeconds: nil,
      maxLongitudinalG: 0.22,
      maxLateralG: -0.08,
      averageSpeedLast1KMKPH: 91,
      averageSpeedLast5KMKPH: 88,
      averageSpeedLast10KMKPH: 85,
      averageSpeedLast1MileKPH: 90,
      averageSpeedLast3MilesKPH: 88,
      averageSpeedLast5MilesKPH: 85
    )
    return store
  }
}
