import Foundation

@MainActor
final class TelemetryStore: ObservableObject {
  @Published var sourceMode: TelemetrySourceMode = .mock
  @Published var telemetry: TelemetrySnapshot = .empty
  @Published var displayTelemetry: TelemetrySnapshot = .empty
  @Published var telemetryHistory: [TelemetrySnapshot] = []
  @Published var displayTelemetryHistory: [TelemetrySnapshot] = []
  @Published var runStats = TelemetryRunStats.empty
  @Published var bluetoothStatus: BluetoothStatus = .unknown
  @Published var diagnostics = BLEDiagnostics()
  @Published var unitSystem: TelemetryUnitSystem = .metric
  @Published var batteryPercent: Int?
  @Published var connectedDeviceName: String?
  @Published var connectedDeviceID: String?
  @Published var sessionSavingEnabled = true
  @Published var savedSessions: [SavedTelemetrySession] = []
  @Published var liveActivityEnabled = true

  private let mockProvider = MockTelemetryProvider()
  private let bluetoothService = DragyBluetoothService()
  private let recorder = TelemetryRecorder()
  private let savedSessionStore = SavedSessionStore()
  private let liveSpeedActivityController = LiveSpeedActivityController()
  private var displayFilter = TelemetryDisplayFilter()
  private var motionEstimator = TelemetryMotionEstimator()
  private let liveActivityDefaultsKey = "dragyDash.liveActivityEnabled"

  init() {
    sessionSavingEnabled = savedSessionStore.isSavingEnabled
    savedSessions = savedSessionStore.loadSessions()
    if UserDefaults.standard.object(forKey: liveActivityDefaultsKey) != nil {
      liveActivityEnabled = UserDefaults.standard.bool(forKey: liveActivityDefaultsKey)
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
    recorder.start()
    runStats = recorder.stats
  }

  func setUnitSystem(_ unitSystem: TelemetryUnitSystem) {
    self.unitSystem = unitSystem
    updateLiveActivity()
  }

  func setSourceMode(_ mode: TelemetrySourceMode) {
    sourceMode = mode
    resetDisplayTelemetry()

    switch mode {
    case .mock:
      bluetoothService.stopScan()
      startMockTelemetry()
    case .bluetooth:
      mockProvider.stop()
      bluetoothService.startScan()
    }
  }

  func startMockTelemetry() {
    guard sourceMode == .mock else {
      return
    }

    mockProvider.start { [weak self] telemetry in
      self?.handleTelemetry(telemetry)
    }
  }

  func scanForDragy() {
    sourceMode = .bluetooth
    resetDisplayTelemetry()
    mockProvider.stop()
    bluetoothService.startScan()
  }

  func stopScanning() {
    bluetoothService.stopScan()
  }

  func connect(to device: BLEDevice) {
    sourceMode = .bluetooth
    resetDisplayTelemetry()
    mockProvider.stop()
    bluetoothService.connect(to: device)
  }

  func writeDiagnosticHex(_ hex: String, targetID: String) {
    bluetoothService.writeDiagnosticHex(hex, targetID: targetID)
  }

  func toggleRecording() {
    if runStats.isRecording {
      recorder.stop()
    } else {
      recorder.start()
    }
    runStats = recorder.stats
  }

  func resetRecording() {
    saveCurrentSession()
    recorder.reset(startRecording: runStats.isRecording)
    telemetryHistory = []
    displayTelemetryHistory = []
    displayFilter.reset()
    motionEstimator.reset()
    runStats = recorder.stats
  }

  func sessionCSV() -> String {
    TelemetrySessionExporter.csv(samples: recorder.samples)
  }

  func setSessionSavingEnabled(_ enabled: Bool) {
    savedSessionStore.setSavingEnabled(enabled)
    sessionSavingEnabled = enabled
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
    guard sessionSavingEnabled, !recorder.samples.isEmpty else {
      return
    }

    do {
      savedSessions = try savedSessionStore.save(csv: sessionCSV())
    } catch {
      savedSessions = savedSessionStore.loadSessions()
    }
  }

  func clearSavedSessions() {
    do {
      try savedSessionStore.clear()
    } catch {
      // Keep the visible state aligned with disk even if one file could not be removed.
    }
    savedSessions = savedSessionStore.loadSessions()
  }

  func diagnosticReport() -> String {
    BLEDiagnosticReport.make(
      status: bluetoothStatus,
      diagnostics: diagnostics,
      telemetry: telemetry,
      batteryPercent: batteryPercent
    )
  }

  private func handleTelemetry(_ telemetry: TelemetrySnapshot) {
    let enrichedTelemetry = motionEstimator.apply(to: telemetry)
    let displayTelemetry = displayFilter.apply(to: enrichedTelemetry)

    self.telemetry = enrichedTelemetry
    self.displayTelemetry = displayTelemetry
    telemetryHistory.append(enrichedTelemetry)
    telemetryHistory = Array(telemetryHistory.suffix(240))
    displayTelemetryHistory.append(displayTelemetry)
    displayTelemetryHistory = Array(displayTelemetryHistory.suffix(240))
    recorder.record(raw: telemetry, statsSnapshot: displayTelemetry)
    runStats = recorder.stats
    updateLiveActivity()
  }

  private func resetDisplayTelemetry() {
    displayFilter.reset()
    motionEstimator.reset()
    displayTelemetry = .empty
    displayTelemetryHistory = []
  }

  private func updateLiveActivity() {
    guard liveActivityEnabled else {
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
    store.telemetryHistory = (0..<60).map { index in
      TelemetrySnapshot(
        timestamp: now.addingTimeInterval(Double(index) * 0.2),
        speedKPH: Double(index) * 2.0,
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
    }
    store.displayTelemetryHistory = store.telemetryHistory
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
      averageSpeedLast5KMKPH: nil,
      averageSpeedLast10KMKPH: nil,
      averageSpeedLast1MileKPH: nil,
      averageSpeedLast3MilesKPH: nil,
      averageSpeedLast5MilesKPH: nil
    )
    return store
  }
}
