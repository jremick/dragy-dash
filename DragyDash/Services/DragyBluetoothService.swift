@preconcurrency import CoreBluetooth
import Foundation

@MainActor
final class DragyBluetoothService: NSObject, @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
  var onStatusChanged: (BluetoothStatus) -> Void = { _ in }
  var onDiagnosticsChanged: (BLEDiagnostics) -> Void = { _ in }
  var onTelemetry: (TelemetrySnapshot) -> Void = { _ in }
  var onBatteryLevelChanged: (Int) -> Void = { _ in }
  var onConnectedDeviceChanged: (String?, String?) -> Void = { _, _ in }

  private var centralManager: CBCentralManager?
  private var peripherals: [UUID: CBPeripheral] = [:]
  private var deviceOrder: [UUID] = []
  private var diagnostics = BLEDiagnostics()
  private let decoder = DragyPacketDecoder()
  private var shouldScanWhenPoweredOn = false
  private var loggedAdvertisements: [UUID: Date] = [:]
  private var loggedCharacteristics = Set<String>()
  private var hasAutoConnectedToCandidate = false
  private weak var connectedPeripheral: CBPeripheral?
  private var writableCharacteristics: [String: CBCharacteristic] = [:]
  private var sppCharacteristic: CBCharacteristic?
  private var sppPollTimer: Timer?
  private var hasStartedSPPPolling = false
  private var hasRespondedToShake = false
  private var packetReassembler = DragyPacketReassembler()

  override init() {
    super.init()
    centralManager = CBCentralManager(delegate: self, queue: .main)
  }

  func startScan() {
    guard let centralManager else {
      return
    }

    switch centralManager.state {
    case .poweredOn:
      onStatusChanged(.scanning)
      log("STATUS scanning")
      centralManager.scanForPeripherals(
        withServices: nil,
        options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
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
    centralManager?.stopScan()
    if centralManager?.state == .poweredOn {
      onStatusChanged(.poweredOn)
    }
  }

  func connect(to device: BLEDevice) {
    guard let peripheral = peripherals[device.id] else {
      onStatusChanged(.failed("Device no longer available"))
      return
    }

    centralManager?.stopScan()
    onStatusChanged(.connecting(device.name))
    peripheral.delegate = self
    centralManager?.connect(peripheral)
  }

  func writeDiagnosticHex(_ hex: String, targetID: String) {
    let normalizedHex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedHex.isEmpty else {
      log("WRITE_SKIPPED empty_payload target=\(targetID)")
      return
    }

    guard let data = Data(hexEncoded: normalizedHex) else {
      log("WRITE_FAILED target=\(targetID) reason=invalid_hex payload=\(normalizedHex)")
      return
    }

    guard let peripheral = connectedPeripheral else {
      log("WRITE_FAILED target=\(targetID) reason=no_connected_peripheral")
      return
    }

    guard let characteristic = writableCharacteristics[targetID] else {
      log("WRITE_FAILED target=\(targetID) reason=target_not_available")
      return
    }

    let writeType: CBCharacteristicWriteType = characteristic.properties.contains(.write) ? .withResponse : .withoutResponse
    let serviceUUID = characteristic.service?.uuid.uuidString ?? "unknown"
    log("WRITE target=\(targetID) service=\(serviceUUID) characteristic=\(characteristic.uuid.uuidString) type=\(writeType.label) bytes=\(data.count) hex=\(data.hexString)")
    peripheral.writeValue(data, for: characteristic, type: writeType)
  }

  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    switch central.state {
    case .poweredOn:
      onStatusChanged(.poweredOn)
      if shouldScanWhenPoweredOn {
        startScan()
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

    peripherals[id] = peripheral
    if !deviceOrder.contains(id) {
      deviceOrder.append(id)
    }

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
    emitDiagnostics()

    logAdvertisement(
      device: device,
      serviceData: serviceData.mapValues(\.hexString)
    )

    if candidate, !hasAutoConnectedToCandidate {
      hasAutoConnectedToCandidate = true
      log("AUTOCONNECT \(device.name) id=\(device.id.uuidString)")
      connect(to: device)
    }
  }

  func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    let name = peripheral.name ?? "Dragy"
    connectedPeripheral = peripheral
    writableCharacteristics.removeAll()
    sppCharacteristic = nil
    stopSPPPolling()
    hasStartedSPPPolling = false
    hasRespondedToShake = false
    packetReassembler.reset()
    diagnostics.characteristics = []
    diagnostics.descriptors = []
    diagnostics.writeTargets = []
    diagnostics.packetSamples = []
    onStatusChanged(.connected(name))
    onConnectedDeviceChanged(name, peripheral.identifier.uuidString)
    log("CONNECTED \(name) id=\(peripheral.identifier.uuidString)")
    peripheral.delegate = self
    peripheral.discoverServices(nil)
  }

  func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
    onStatusChanged(.failed(error?.localizedDescription ?? "Failed to connect"))
    log("CONNECT_FAILED id=\(peripheral.identifier.uuidString) error=\(error?.localizedDescription ?? "unknown")")
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
    onConnectedDeviceChanged(nil, nil)
    writableCharacteristics.removeAll()
    sppCharacteristic = nil
    stopSPPPolling()
    hasStartedSPPPolling = false
    hasRespondedToShake = false
    packetReassembler.reset()
  }

  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    guard error == nil, let services = peripheral.services else {
      onStatusChanged(.failed(error?.localizedDescription ?? "Service discovery failed"))
      log("SERVICE_DISCOVERY_FAILED error=\(error?.localizedDescription ?? "unknown")")
      return
    }

    for service in services {
      log("SERVICE uuid=\(service.uuid.uuidString)")
      peripheral.discoverCharacteristics(nil, for: service)
    }
  }

  func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
    guard error == nil, let characteristics = service.characteristics else {
      onStatusChanged(.failed(error?.localizedDescription ?? "Characteristic discovery failed"))
      log("CHARACTERISTIC_DISCOVERY_FAILED service=\(service.uuid.uuidString) error=\(error?.localizedDescription ?? "unknown")")
      return
    }

    for characteristic in characteristics {
      let info = BLECharacteristicInfo(
        serviceUUID: service.uuid.uuidString,
        characteristicUUID: characteristic.uuid.uuidString,
        properties: characteristic.properties.labels
      )
      diagnostics.characteristics.removeAll { $0.id == info.id }
      diagnostics.characteristics.append(info)
      logCharacteristic(info)

      if DragySPPProtocol.isSPPCharacteristic(uuid: characteristic.uuid.uuidString) {
        sppCharacteristic = characteristic
        log("SPP_TARGET characteristic=\(characteristic.uuid.uuidString) service=\(service.uuid.uuidString)")
      }

      if characteristic.properties.contains(.write) || characteristic.properties.contains(.writeWithoutResponse) {
        writableCharacteristics[info.id] = characteristic
        diagnostics.writeTargets.removeAll { $0.id == info.id }
        diagnostics.writeTargets.append(BLEWriteTarget(
          serviceUUID: service.uuid.uuidString,
          characteristicUUID: characteristic.uuid.uuidString,
          label: nil,
          properties: info.properties
        ))
      }

      if characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) {
        log("SUBSCRIBE characteristic=\(characteristic.uuid.uuidString) service=\(service.uuid.uuidString)")
        peripheral.setNotifyValue(true, for: characteristic)
      }

      log("DISCOVER_DESCRIPTORS characteristic=\(characteristic.uuid.uuidString) service=\(service.uuid.uuidString)")
      peripheral.discoverDescriptors(for: characteristic)

      if characteristic.properties.contains(.read) {
        log("READ characteristic=\(characteristic.uuid.uuidString) service=\(service.uuid.uuidString)")
        peripheral.readValue(for: characteristic)
      }
    }

    diagnostics.characteristics.sort { $0.id < $1.id }
    diagnostics.writeTargets.sort { $0.id < $1.id }
    emitDiagnostics()
  }

  func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
    let serviceUUID = characteristic.service?.uuid.uuidString ?? "unknown"
    if let error {
      log("NOTIFY_STATE_FAILED characteristic=\(characteristic.uuid.uuidString) service=\(serviceUUID) error=\(error.localizedDescription)")
    } else {
      log("NOTIFY_STATE characteristic=\(characteristic.uuid.uuidString) service=\(serviceUUID) enabled=\(characteristic.isNotifying)")
      if characteristic.isNotifying, DragySPPProtocol.isSPPCharacteristic(uuid: characteristic.uuid.uuidString) {
        startSPPPollingIfNeeded()
      }
    }
  }

  func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: Error?) {
    let serviceUUID = characteristic.service?.uuid.uuidString ?? "unknown"
    guard error == nil, let descriptors = characteristic.descriptors else {
      log("DESCRIPTOR_DISCOVERY_FAILED characteristic=\(characteristic.uuid.uuidString) service=\(serviceUUID) error=\(error?.localizedDescription ?? "unknown")")
      return
    }

    for descriptor in descriptors {
      log("DESCRIPTOR service=\(serviceUUID) characteristic=\(characteristic.uuid.uuidString) descriptor=\(descriptor.uuid.uuidString)")
      peripheral.readValue(for: descriptor)
    }
  }

  func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
    guard error == nil, let data = characteristic.value else {
      return
    }

    let sample = BLEPacketSample(
      timestamp: .now,
      characteristicUUID: characteristic.uuid.uuidString,
      hex: data.hexString,
      asciiPreview: data.asciiPreview
    )
    if sample.characteristicUUID.uppercased() != "FD02" {
      log("PACKET characteristic=\(sample.characteristicUUID) bytes=\(data.count) hex=\(sample.hex) ascii=\(sample.asciiPreview ?? "")")
    }
    diagnostics.packetSamples.insert(sample, at: 0)
    diagnostics.packetSamples = Array(diagnostics.packetSamples.prefix(24))
    emitDiagnostics()

    respondToShakeChallengeIfNeeded(data, characteristic: characteristic, peripheral: peripheral)
    parseDeviceStatusIfNeeded(data, characteristic: characteristic)

    if let sppResult = DragySPPProtocol.parseReadResult(data) {
      let rawValue = sppResult.rawValue.map(String.init) ?? "nil"
      let speed = sppResult.speedKPH.map { String(format: "%.3f", $0) } ?? "nil"
      log("SPP_READ_RESULT feature=\(sppResult.feature.displayName) raw=\(rawValue) speed_kph=\(speed)")
    }

    let packets = packetReassembler.packets(from: data, characteristicUUID: characteristic.uuid.uuidString)
    for packet in packets {
      if packet != data {
        log("REASSEMBLED characteristic=\(characteristic.uuid.uuidString) bytes=\(packet.count) hex_prefix=\(packet.prefix(16).hexString)")
      }

      if let snapshot = decoder.decode(
        packet,
        characteristicUUID: characteristic.uuid.uuidString,
        sourceName: peripheral.name ?? "Dragy Pro"
      ) {
        log("TELEMETRY speed_kph=\(String(format: "%.3f", snapshot.speedKPH)) fix=\(snapshot.fixQuality.rawValue)")
        onTelemetry(snapshot)
      }
    }
  }

  func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor descriptor: CBDescriptor, error: Error?) {
    let characteristic = descriptor.characteristic
    let characteristicUUID = characteristic?.uuid.uuidString ?? "unknown"
    let serviceUUID = characteristic?.service?.uuid.uuidString ?? "unknown"

    guard error == nil else {
      log("DESCRIPTOR_VALUE_FAILED descriptor=\(descriptor.uuid.uuidString) characteristic=\(characteristicUUID) service=\(serviceUUID) error=\(error?.localizedDescription ?? "unknown")")
      return
    }

    let info = BLEDescriptorInfo(
      serviceUUID: serviceUUID,
      characteristicUUID: characteristicUUID,
      descriptorUUID: descriptor.uuid.uuidString,
      valueDescription: descriptorValueDescription(descriptor.value)
    )
    diagnostics.descriptors.removeAll { $0.id == info.id }
    diagnostics.descriptors.append(info)
    diagnostics.descriptors.sort { $0.id < $1.id }
    applyDescriptorLabel(info, descriptor: descriptor)
    emitDiagnostics()

    log("DESCRIPTOR_VALUE service=\(serviceUUID) characteristic=\(characteristicUUID) descriptor=\(descriptor.uuid.uuidString) value=\(info.valueDescription ?? "")")
  }

  func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
    let serviceUUID = characteristic.service?.uuid.uuidString ?? "unknown"
    if let error {
      log("WRITE_ACK_FAILED service=\(serviceUUID) characteristic=\(characteristic.uuid.uuidString) error=\(error.localizedDescription)")
    } else {
      log("WRITE_ACK service=\(serviceUUID) characteristic=\(characteristic.uuid.uuidString)")
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

    if advertisedServiceUUIDs.contains("FD00") {
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

  private func applyDescriptorLabel(_ info: BLEDescriptorInfo, descriptor: CBDescriptor) {
    guard descriptor.uuid == CBUUID(string: "2901"), let label = info.valueDescription else {
      return
    }

    let targetID = "\(info.serviceUUID).\(info.characteristicUUID)"
    guard let index = diagnostics.writeTargets.firstIndex(where: { $0.id == targetID }) else {
      return
    }

    diagnostics.writeTargets[index].label = label
    diagnostics.writeTargets.sort { $0.id < $1.id }
  }

  private func parseDeviceStatusIfNeeded(_ data: Data, characteristic: CBCharacteristic) {
    guard characteristic.uuid.uuidString.uppercased() == "FD04" else {
      return
    }

    guard let batteryPercent = DragyDeviceStatusDecoder.batteryPercent(from: data) else {
      log("DEVICE_STATUS battery=unknown bytes=\(data.count) hex=\(data.hexString)")
      return
    }

    log("DEVICE_STATUS battery_percent=\(batteryPercent) hex=\(data.hexString)")
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
    log("SHAKE_RESPONSE challenge=\(data.hexString) response=\(response.hexString) type=\(writeType.label)")
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
    log("SPP_READ feature=\(feature.displayName) service=\(serviceUUID) characteristic=\(characteristic.uuid.uuidString) type=\(writeType.label) hex=\(data.hexString)")
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
      "ADVERTISEMENT name=\(device.name) id=\(device.id.uuidString) rssi=\(device.rssi) candidate=\(device.isDragyCandidate) localName=\(device.localName ?? "") manufacturer=\(device.manufacturerDataHex ?? "") services=\(services) serviceData=\(serviceDataText)"
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
    print("DRAGYDASH_BLE \(message)")
    diagnostics.events.insert(BLELogEvent(timestamp: .now, message: message), at: 0)
    diagnostics.events = Array(diagnostics.events.prefix(80))
    emitDiagnostics()
  }
}

private func descriptorValueDescription(_ value: Any?) -> String? {
  guard let value else {
    return nil
  }

  if let data = value as? Data {
    let ascii = data.asciiPreview.map { " ascii=\($0)" } ?? ""
    return "hex=\(data.hexString)\(ascii)"
  }

  if let string = value as? String {
    return string
  }

  if let number = value as? NSNumber {
    return number.stringValue
  }

  if let uuid = value as? CBUUID {
    return uuid.uuidString
  }

  if let uuids = value as? [CBUUID] {
    return uuids.map(\.uuidString).joined(separator: ", ")
  }

  return String(describing: value)
}

private extension Data {
  init?(hexEncoded string: String) {
    let allowedSeparators = CharacterSet(charactersIn: " ,:-_\n\r\t")
    let compact = string.unicodeScalars.filter { !allowedSeparators.contains($0) }
    guard compact.count.isMultiple(of: 2) else {
      return nil
    }

    var bytes: [UInt8] = []
    bytes.reserveCapacity(compact.count / 2)

    var index = compact.startIndex
    while index < compact.endIndex {
      let nextIndex = compact.index(after: index)
      guard nextIndex < compact.endIndex else {
        return nil
      }

      let byteString = String(String.UnicodeScalarView([compact[index], compact[nextIndex]]))
      guard let byte = UInt8(byteString, radix: 16) else {
        return nil
      }

      bytes.append(byte)
      index = compact.index(after: nextIndex)
    }

    self.init(bytes)
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
