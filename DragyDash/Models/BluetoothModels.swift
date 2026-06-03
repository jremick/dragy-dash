import Foundation

enum BluetoothStatus: Equatable {
  case unknown
  case resetting
  case unsupported
  case unauthorized
  case poweredOff
  case poweredOn
  case scanning
  case connecting(String)
  case connected(String)
  case failed(String)

  var label: String {
    switch self {
    case .unknown:
      "Bluetooth unknown"
    case .resetting:
      "Bluetooth resetting"
    case .unsupported:
      "Bluetooth unsupported"
    case .unauthorized:
      "Bluetooth permission needed"
    case .poweredOff:
      "Bluetooth off"
    case .poweredOn:
      "Bluetooth ready"
    case .scanning:
      "Scanning"
    case .connecting(let name):
      "Connecting to \(name)"
    case .connected(let name):
      "Connected to \(name)"
    case .failed(let message):
      message
    }
  }
}

struct BLEDevice: Identifiable, Equatable {
  let id: UUID
  var name: String
  var rssi: Int
  var isDragyCandidate: Bool
  var localName: String?
  var manufacturerDataHex: String?
  var advertisedServiceUUIDs: [String]
  var lastSeen: Date
}

struct BLECharacteristicInfo: Identifiable, Equatable {
  var id: String { "\(serviceUUID).\(characteristicUUID)" }
  let serviceUUID: String
  let characteristicUUID: String
  let properties: [String]
}

struct BLEDescriptorInfo: Identifiable, Equatable {
  var id: String { "\(serviceUUID).\(characteristicUUID).\(descriptorUUID)" }
  let serviceUUID: String
  let characteristicUUID: String
  let descriptorUUID: String
  let valueDescription: String?
}

struct BLEWriteTarget: Identifiable, Equatable {
  var id: String { "\(serviceUUID).\(characteristicUUID)" }
  let serviceUUID: String
  let characteristicUUID: String
  var label: String?
  let properties: [String]

  var displayName: String {
    label ?? characteristicUUID
  }
}

struct BLEPacketSample: Identifiable, Equatable {
  let id = UUID()
  let timestamp: Date
  let characteristicUUID: String
  let hex: String
  let asciiPreview: String?
}

struct BLELogEvent: Identifiable, Equatable {
  let id = UUID()
  let timestamp: Date
  let message: String
}

struct BLEDiagnostics: Equatable {
  var devices: [BLEDevice] = []
  var characteristics: [BLECharacteristicInfo] = []
  var descriptors: [BLEDescriptorInfo] = []
  var writeTargets: [BLEWriteTarget] = []
  var packetSamples: [BLEPacketSample] = []
  var events: [BLELogEvent] = []
}
