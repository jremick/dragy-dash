@preconcurrency import CoreBluetooth
import Foundation
import OSLog

@MainActor
final class DragyBluetoothService: NSObject, @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
  var onStatusChanged: (BluetoothStatus) -> Void = { _ in }
  var onDiagnosticsChanged: (BLEDiagnostics) -> Void = { _ in }
  var onTelemetry: (TelemetrySnapshot) -> Void = { _ in }
  var onBatteryLevelChanged: (Int?) -> Void = { _ in }
  var onConnectedDeviceChanged: (String?, String?) -> Void = { _, _ in }
  var onDisconnected: () -> Void = { }

  private static let dragyServiceUUID = CBUUID(string: "FD00")
  private static let deviceInfoServiceUUID = CBUUID(string: "180A")
  private static let lastPeripheralIDKey = "dragyDash.lastPeripheralID"
  private static let logger = Logger(subsystem: "com.dragydash.ble", category: "bluetooth")

  private var centralManager: CBCentralManager?
  private var peripherals: [UUID: CBPeripheral] = [:]
  private var diagnostics = BLEDiagnostics()
  private let decoder = DragyPacketDecoder()
  private var shouldScanWhenPoweredOn = false
  private var scanAllDevices = false
  private var autoReconnectEnabled = true
  private var loggedAdvertisements: [UUID: Date] = [:]
  private var loggedCharacteristics = Set<String>()
  private var hasAutoConnectedToCandidate = false
  private weak var connectedPeripheral: CBPeripheral?
  private var handshakeCharacteristic: CBCharacteristic?
  private var isTelemetryNotifying = false
  private var hasRequestedHandshakeRead = false
  private var hasRespondedToShake = false
  private var sppCharacteristic: CBCharacteristic?
  private var sppPollTimer: Timer?
  private var hasStartedSPPPolling = false
  private var hasAttemptedLegacyServiceDiscovery = false
  private var reconnectTask: Task<Void, Never>?
  private var lastPacketDiagnosticsEmit: Date = .distantPast
  private var packetReassembler = DragyPacketReassembler()

  override init() {
    super.init()
    centralManager = CBCentralManager(delegate: self, queue: .main)
  }

  func startScan(includeAllDevices: Bool = false) {
    guard let centralManager else {
      return
    }

    reconnectTask?.cancel()
    reconnectTask = nil
    scanAllDevices = includeAllDevices
    autoReconnectEnabled = true
    hasAutoConnectedToCandidate = false

    switch centralManager.state {
    case .poweredOn:
      // Clear stale peripheral entries from earlier scans so the cache stays bounded.
      if connectedPeripheral == nil {
        peripherals.removeAll()
        loggedAdvertisements.removeAll()
        diagnostics.devices.removeAll()
        emitDiagnostics()
      }

      onStatusChanged(.scanning)
      log("STATUS scanning targeted=\(!includeAllDevices)")
      let services: [CBUUID]? = includeAllDevices ? nil : [Self.dragyServiceUUID]
      centralManager.scanForPeripherals(
        withServices: services,
        options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
      )
    case .unknown, .resetting:
      shouldScanWhenPoweredOn = true
      onStatusChanged(.unknown)
      log("STATUS waiting_for_powered_on")
    case .unsupported:
      onStatusChanged(.unsupported)
      log("STATUS unsupported")
    case .unauthorized:
      onStatusChanged(.unauthorized)
      log("STATUS unauthorized")
    case .poweredOff:
      onStatusChanged(.poweredOff)
      log("STATUS powered_off")
    @unknown default:
      onStatusChanged(.unknown)
      log("STATUS unknown")
    }
  }

  func stopScan() {
    shouldScanWhenPoweredOn = false
    autoReconnectEnabled = false
    reconnectTask?.cancel()
    reconnectTask = nil
    centralManager?.stopScan()
    if connectedPeripheral == nil, centralManager?.state == .poweredOn {
      onStatusChanged(.poweredOn)
    }
  }

  func disconnect() {
    shouldScanWhenPoweredOn = false
    autoReconnectEnabled = false
    hasAutoConnectedToCandidate = false
    reconnectTask?.cancel()
    reconnectTask = nil
    centralManager?.stopScan()

    if let peripheral = connectedPeripheral {
      centralManager?.cancelPeripheralConnection(peripheral)
    } else if centralManager?.state == .poweredOn {
      onStatusChanged(.poweredOn)
    }
  }

  func connect(to device: BLEDevice) {
    guard let peripheral = peripherals[device.id] else {
      onStatusChanged(.failed("Device no longer available"))
      return
    }

    reconnectTask?.cancel()
    reconnectTask = nil
    autoReconnectEnabled = true
    hasAutoConnectedToCandidate = true
    centralManager?.stopScan()
    onStatusChanged(.connecting(device.name))
    peripheral.delegate = self
    centralManager?.connect(peripheral)
  }

  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    switch central.state {
    case .poweredOn:
      onStatusChanged(.poweredOn)
      if shouldScanWhenPoweredOn {
        shouldScanWhenPoweredOn = false
        startScan(includeAllDevices: scanAllDevices)
      }
    case .resetting:
      onStatusChanged(.resetting)
    case .unsupported:
      onStatusChanged(.unsupported)
    case .unauthorized:
      onStatusChanged(.unauthorized)
    case .poweredOff:
      onStatusChanged(.poweredOff)
    case .unknown:
      onStatusChanged(.unknown)
    @unknown default:
      onStatusChanged(.unknown)
    }
  }

  func centralManager(
    _ central: CBCentralManager,
    didDiscover peripheral: CBPeripheral,
    advertisementData: [String: Any],
    rssi RSSI: NSNumber
  ) {
    let id = peripheral.identifier
    let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
    let name = localName ?? peripheral.name ?? "Unknown BLE Device"
    let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
    let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
    let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data] ?? [:]
    let advertisedServiceUUIDs = services.map(\.uuidString).sorted()
    let candidate = isDragyCandidate(
      name: name,
      localName: localName,
      manufacturerData: manufacturerData,
      advertisedServiceUUIDs: advertisedServiceUUIDs
    )

    if !candidate && !scanAllDevices {
      return
    }

    peripherals[id] = peripheral

    let device = BLEDevice(
      id: id,
      name: name,
      rssi: RSSI.intValue,
      isDragyCandidate: candidate,
      localName: localName,
      manufacturerDataHex: manufacturerData?.hexString,
      advertisedServiceUUIDs: advertisedServiceUUIDs,
      lastSeen: .now
    )

    diagnostics.devices.removeAll { $0.id == id }
    diagnostics.devices.append(device)
    diagnostics.devices.sort {
      if $0.isDragyCandidate != $1.isDragyCandidate {
        return $0.isDragyCandidate
      }
      return $0.rssi > $1.rssi
    }
    if diagnostics.devices.count > 32 {
      diagnostics.devices = Array(diagnostics.devices.prefix(32))
    }
    emitDiagnostics()

    logAdvertisement(
      device: device,
      serviceData: serviceData.mapValues(\.hexString)
    )

    let preferredID = UserDefaults.standard.string(forKey: Self.lastPeripheralIDKey)
    let isPreferred = preferredID == nil || preferredID == device.id.uuidString
    if candidate, connectedPeripheral == nil, !hasAutoConnectedToCandidate, isPreferred || diagnostics.devices.count == 1 {
      hasAutoConnectedToCandidate = true
      log("AUTOCONNECT \(device.name) id=\(device.id.uuidString)")
      connect(to: device)
    }
  }

  func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    let name = peripheral.name ?? "Dragy"
    connectedPeripheral = peripheral
    UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: Self.lastPeripheralIDKey)
    resetConnectionState()
    diagnostics.characteristics = []
    diagnostics.descriptors = []
    diagnostics.writeTargets = []
    diagnostics.packetSamples = []
    emitDiagnostics()
    onStatusChanged(.connected(name))
    onConnectedDeviceChanged(name, peripheral.identifier.uuidString)
    log("CONNECTED \(name) id=\(peripheral.identifier.uuidString)")
    peripheral.delegate = self
    peripheral.discoverServices([Self.dragyServiceUUID, Self.deviceInfoServiceUUID])
  }

  func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
    hasAutoConnectedToCandidate = false
    onStatusChanged(.failed(error?.localizedDescription ?? "Failed to connect"))
    log("CONNECT_FAILED id=\(peripheral.identifier.uuidString) error=\(error?.localizedDescription ?? "unknown")")
    scheduleReconnectIfEnabled()
  }

  func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
    if let error {
      onStatusChanged(.failed(error.localizedDescription))
      log("DISCONNECTED_WITH_ERROR id=\(peripheral.identifier.uuidString) error=\(error.localizedDescription)")
    } else {
      onStatusChanged(.poweredOn)
      log("DISCONNECTED id=\(peripheral.identifier.uuidString)")
    }

    connectedPeripheral = nil
    hasAutoConnectedToCandidate = false
    resetConnectionState()
    onConnectedDeviceChanged(nil, nil)
    onBatteryLevelChanged(nil)
    onDisconnected()

    scheduleReconnectIfEnabled()
  }

  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    guard error == nil, let services = peripheral.services else {
      onStatusChanged(.failed(error?.localizedDescription ?? "Service discovery failed"))
      log("SERVICE_DISCOVERY_FAILED error=\(error?.localizedDescription ?? "unknown")")
      return
    }

    let hasFD00 = services.contains { $0.uuid.uuidString.uppercased() == "FD00" }
    if !hasFD00 && !hasAttemptedLegacyServiceDiscovery {
      hasAttemptedLegacyServiceDiscovery = true
      log("SERVICE_FALLBACK reason=no_fd00 action=discover_all_services")
      peripheral.discoverServices(nil)
      return
    }

    for service in services {
      log("SERVICE uuid=\(service.uuid.uuidString)")
      let uuid = service.uuid.uuidString.uppercased()
      if uuid == "FD00" || uuid == "180A" || !hasFD00 {
        peripheral.discoverCharacteristics(nil, for: service)
      }
    }
  }

  func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
    guard error == nil, let characteristics = service.characteristics else {
      onStatusChanged(.failed(error?.localizedDescription ?? "Characteristic discovery failed"))
      log("CHARACTERISTIC_DISCOVERY_FAILED service=\(service.uuid.uuidString) error=\(error?.localizedDescription ?? "unknown")")
      return
    }

    let serviceUUID = service.uuid.uuidString.uppercased()

    for characteristic in characteristics {
      let charUUID = characteristic.uuid.uuidString.uppercased()
      let info = BLECharacteristicInfo(
        serviceUUID: service.uuid.uuidString,
        characteristicUUID: characteristic.uuid.uuidString,
        properties: characteristic.properties.labels
      )
      diagnostics.characteristics.removeAll { $0.id == info.id }
      diagnostics.characteristics.append(info)
      logCharacteristic(info)

      if DragySPPProtocol.isSPPCharacteristic(uuid: charUUID) {
        sppCharacteristic = characteristic
        log("SPP_TARGET characteristic=\(characteristic.uuid.uuidString) service=\(service.uuid.uuidString)")
        if characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) {
          peripheral.setNotifyValue(true, for: characteristic)
        }
        continue
      }

      if serviceUUID == "FD00" {
        // Interact strictly with observed telemetry/handshake/status characteristics.
        // Avoid probing MCU update (FD05) or factory test (FD11) characteristics.
        switch charUUID {
        case "FD02":
          if characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) {
            log("SUBSCRIBE characteristic=\(characteristic.uuid.uuidString) service=\(service.uuid.uuidString)")
            peripheral.setNotifyValue(true, for: characteristic)
          }
        case "FD03":
          handshakeCharacteristic = characteristic
          beginHandshakeIfReady(peripheral: peripheral)
        case "FD04":
          if characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) {
            log("SUBSCRIBE characteristic=\(characteristic.uuid.uuidString) service=\(service.uuid.uuidString)")
            peripheral.setNotifyValue(true, for: characteristic)
          }
          if characteristic.properties.contains(.read) {
            log("READ characteristic=\(characteristic.uuid.uuidString) service=\(service.uuid.uuidString)")
            peripheral.readValue(for: characteristic)
          }
        default:
          break
        }
      }
    }

    diagnostics.characteristics.sort { $0.id < $1.id }
    emitDiagnostics()
  }

  func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
    let serviceUUID = characteristic.service?.uuid.uuidString ?? "unknown"
    let charUUID = characteristic.uuid.uuidString.uppercased()
    if let error {
      log("NOTIFY_STATE_FAILED characteristic=\(characteristic.uuid.uuidString) service=\(serviceUUID) error=\(error.localizedDescription)")
    } else {
      log("NOTIFY_STATE characteristic=\(characteristic.uuid.uuidString) service=\(serviceUUID) enabled=\(characteristic.isNotifying)")
      if characteristic.isNotifying && charUUID == "FD02" {
        isTelemetryNotifying = true
        beginHandshakeIfReady(peripheral: peripheral)
      }
      if characteristic.isNotifying, DragySPPProtocol.isSPPCharacteristic(uuid: charUUID) {
        startSPPPollingIfNeeded()
      }
    }
  }

  func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
    guard error == nil, let data = characteristic.value else {
      return
    }

    let charUUID = characteristic.uuid.uuidString
    let isTelemetryFragment = charUUID.uppercased() == "FD02"

    if !isTelemetryFragment {
      let sample = BLEPacketSample(
        timestamp: .now,
        characteristicUUID: charUUID,
        hex: data.hexString,
        asciiPreview: data.asciiPreview
      )
      log("PACKET characteristic=\(sample.characteristicUUID) bytes=\(data.count) hex=\(sample.hex) ascii=\(sample.asciiPreview ?? "")")
      diagnostics.packetSamples.insert(sample, at: 0)
      diagnostics.packetSamples = Array(diagnostics.packetSamples.prefix(24))
      emitDiagnostics()
    } else {
      // Avoid allocating hex strings or invalidating SwiftUI views on every raw FD02 fragment.
      let now = Date()
      if now.timeIntervalSince(lastPacketDiagnosticsEmit) >= 1.0 {
        lastPacketDiagnosticsEmit = now
        let sample = BLEPacketSample(
          timestamp: now,
          characteristicUUID: charUUID,
          hex: data.hexString,
          asciiPreview: nil
        )
        diagnostics.packetSamples.insert(sample, at: 0)
        diagnostics.packetSamples = Array(diagnostics.packetSamples.prefix(24))
      }
    }

    respondToShakeChallengeIfNeeded(data, characteristic: characteristic, peripheral: peripheral)
    parseDeviceStatusIfNeeded(data, characteristic: characteristic)

    if let sppResult = DragySPPProtocol.parseReadResult(data) {
      let rawValue = sppResult.rawValue.map(String.init) ?? "nil"
      let speed = sppResult.speedKPH.map { String(format: "%.3f", $0) } ?? "nil"
      log("SPP_READ_RESULT feature=\(sppResult.feature.displayName) raw=\(rawValue) speed_kph=\(speed)")
    }

    let packets = packetReassembler.packets(from: data, characteristicUUID: charUUID)
    for packet in packets {
      if let snapshot = decoder.decode(
        packet,
        characteristicUUID: charUUID,
        sourceName: peripheral.name ?? "Dragy Pro"
      ) {
        onTelemetry(snapshot)
      }
    }
  }

  func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
    let serviceUUID = characteristic.service?.uuid.uuidString ?? "unknown"
    if let error {
      log("WRITE_ACK_FAILED service=\(serviceUUID) characteristic=\(characteristic.uuid.uuidString) error=\(error.localizedDescription)")
    } else {
      log("WRITE_ACK service=\(serviceUUID) characteristic=\(characteristic.uuid.uuidString)")
    }
  }

  private func resetConnectionState() {
    handshakeCharacteristic = nil
    isTelemetryNotifying = false
    hasRequestedHandshakeRead = false
    hasRespondedToShake = false
    sppCharacteristic = nil
    stopSPPPolling()
    hasStartedSPPPolling = false
    hasAttemptedLegacyServiceDiscovery = false
    loggedCharacteristics.removeAll()
    packetReassembler.reset()
  }

  private func beginHandshakeIfReady(peripheral: CBPeripheral) {
    guard isTelemetryNotifying,
          !hasRequestedHandshakeRead,
          let fd03 = handshakeCharacteristic,
          fd03.properties.contains(.read) else {
      return
    }

    hasRequestedHandshakeRead = true
    log("READ characteristic=\(fd03.uuid.uuidString) service=FD00")
    peripheral.readValue(for: fd03)
  }

  private func scheduleReconnectIfEnabled() {
    guard autoReconnectEnabled else {
      return
    }

    reconnectTask?.cancel()
    reconnectTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(2))
      guard let self, !Task.isCancelled, self.autoReconnectEnabled, self.connectedPeripheral == nil else {
        return
      }
      self.startScan(includeAllDevices: self.scanAllDevices)
    }
  }

  private func isDragyCandidate(
    name: String,
    localName: String?,
    manufacturerData: Data?,
    advertisedServiceUUIDs: [String]
  ) -> Bool {
    let joined = [name, localName].compactMap(\.self).joined(separator: " ").lowercased()
    if joined.contains("dragy") || joined.contains("drg70") || joined.contains("drg69") || joined.hasPrefix("drg") {
      return true
    }

    if advertisedServiceUUIDs.contains(where: { $0.uppercased() == "FD00" }) {
      return true
    }

    guard let manufacturerData else {
      return false
    }

    return manufacturerData.asciiPreview?.lowercased().contains("dragy") == true
  }

  private func emitDiagnostics() {
    onDiagnosticsChanged(diagnostics)
  }

  private func parseDeviceStatusIfNeeded(_ data: Data, characteristic: CBCharacteristic) {
    guard characteristic.uuid.uuidString.uppercased() == "FD04" else {
      return
    }

    guard let batteryPercent = DragyDeviceStatusDecoder.batteryPercent(from: data) else {
      log("DEVICE_STATUS battery=unknown bytes=\(data.count)")
      return
    }

    log("DEVICE_STATUS battery_percent=\(batteryPercent)")
    onBatteryLevelChanged(batteryPercent)
  }

  private func respondToShakeChallengeIfNeeded(
    _ data: Data,
    characteristic: CBCharacteristic,
    peripheral: CBPeripheral
  ) {
    guard characteristic.uuid.uuidString.uppercased() == "FD03", !hasRespondedToShake else {
      return
    }

    let bytes = Array(data)
    guard bytes.count >= 2 else {
      log("SHAKE_RESPONSE_SKIPPED reason=short_challenge bytes=\(bytes.count)")
      return
    }

    let response = Data([bytes[0], bytes[1], bytes[0] ^ bytes[1], bytes[0] & bytes[1]])
    let writeType: CBCharacteristicWriteType = characteristic.properties.contains(.write) ? .withResponse : .withoutResponse
    hasRespondedToShake = true
    log("SHAKE_RESPONSE bytes=\(response.count) type=\(writeType.label)")
    peripheral.writeValue(response, for: characteristic, type: writeType)
  }

  private func startSPPPollingIfNeeded() {
    guard !hasStartedSPPPolling else {
      return
    }

    hasStartedSPPPolling = true
    sendSPPRead(.currentSpeed)
    sendSPPRead(.maxSpeed)
    sendSPPRead(.recordState)

    sppPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
      Task { @MainActor in
        self?.sendSPPRead(.currentSpeed)
      }
    }
  }

  private func sendSPPRead(_ feature: DragySPPFeature) {
    guard let peripheral = connectedPeripheral, let characteristic = sppCharacteristic else {
      log("SPP_READ_SKIPPED feature=\(feature.displayName) reason=no_spp_characteristic")
      return
    }

    let data = DragySPPProtocol.readFrame(for: feature)
    let writeType: CBCharacteristicWriteType = characteristic.properties.contains(.write) ? .withResponse : .withoutResponse
    let serviceUUID = characteristic.service?.uuid.uuidString ?? "unknown"
    log("SPP_READ feature=\(feature.displayName) service=\(serviceUUID) characteristic=\(characteristic.uuid.uuidString) type=\(writeType.label)")
    peripheral.writeValue(data, for: characteristic, type: writeType)
  }

  private func stopSPPPolling() {
    sppPollTimer?.invalidate()
    sppPollTimer = nil
  }

  private func logAdvertisement(device: BLEDevice, serviceData: [CBUUID: String]) {
    let now = Date()
    if let previous = loggedAdvertisements[device.id], now.timeIntervalSince(previous) < 10 {
      return
    }

    loggedAdvertisements[device.id] = now
    let services = device.advertisedServiceUUIDs.joined(separator: "|")
    let serviceDataText = serviceData
      .map { "\($0.key.uuidString)=\($0.value)" }
      .sorted()
      .joined(separator: "|")
    log(
      "ADVERTISEMENT name=\(device.name) id=\(device.id.uuidString) rssi=\(device.rssi) candidate=\(device.isDragyCandidate) services=\(services) serviceData=\(serviceDataText)"
    )
  }

  private func logCharacteristic(_ info: BLECharacteristicInfo) {
    guard !loggedCharacteristics.contains(info.id) else {
      return
    }

    loggedCharacteristics.insert(info.id)
    log(
      "CHARACTERISTIC service=\(info.serviceUUID) characteristic=\(info.characteristicUUID) properties=\(info.properties.joined(separator: "|"))"
    )
  }

  private func log(_ message: String) {
    Self.logger.debug("\(message, privacy: .private)")
    diagnostics.events.insert(BLELogEvent(timestamp: .now, message: message), at: 0)
    diagnostics.events = Array(diagnostics.events.prefix(80))
    emitDiagnostics()
  }
}

private extension CBCharacteristicWriteType {
  var label: String {
    switch self {
    case .withResponse:
      "withResponse"
    case .withoutResponse:
      "withoutResponse"
    @unknown default:
      "unknown"
    }
  }
}

private extension CBCharacteristicProperties {
  var labels: [String] {
    var values: [String] = []
    if contains(.read) { values.append("read") }
    if contains(.write) { values.append("write") }
    if contains(.writeWithoutResponse) { values.append("writeWithoutResponse") }
    if contains(.notify) { values.append("notify") }
    if contains(.indicate) { values.append("indicate") }
    if contains(.broadcast) { values.append("broadcast") }
    if contains(.authenticatedSignedWrites) { values.append("authenticatedSignedWrites") }
    if contains(.extendedProperties) { values.append("extendedProperties") }
    if contains(.notifyEncryptionRequired) { values.append("notifyEncryptionRequired") }
    if contains(.indicateEncryptionRequired) { values.append("indicateEncryptionRequired") }
    return values
  }
}
