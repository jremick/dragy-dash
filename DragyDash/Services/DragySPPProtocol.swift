import Foundation

enum DragySPPFeature: CaseIterable, Equatable {
  case currentSpeed
  case maxSpeed
  case recordState
  case diskFree
  case diskSpace

  var displayName: String {
    switch self {
    case .currentSpeed:
      "datasp_current_speed"
    case .maxSpeed:
      "datasp_max_speed"
    case .recordState:
      "mem_record_state"
    case .diskFree:
      "mem_disk_free"
    case .diskSpace:
      "mem_disk_space"
    }
  }

  var address: [UInt8] {
    switch self {
    case .currentSpeed:
      [0x00, 0x00, 0x00, 0x00, 0x00, 0x20, 0x7C, 0x84]
    case .maxSpeed:
      [0x00, 0x00, 0x00, 0x00, 0x00, 0x20, 0x7C, 0x80]
    case .recordState:
      [0x00, 0x00, 0x00, 0x00, 0x00, 0x20, 0x7C, 0xC0]
    case .diskFree:
      [0x00, 0x00, 0x00, 0x00, 0x00, 0x20, 0x7C, 0xCC]
    case .diskSpace:
      [0x00, 0x00, 0x00, 0x00, 0x00, 0x20, 0x7C, 0xD0]
    }
  }

  var isSpeed: Bool {
    self == .currentSpeed || self == .maxSpeed
  }
}

struct DragySPPReadResult: Equatable {
  let feature: DragySPPFeature
  let value: Data

  var rawValue: UInt64? {
    let bytes = Array(value.prefix(8))
    guard !bytes.isEmpty else {
      return nil
    }

    return bytes.enumerated().reduce(UInt64(0)) { partial, item in
      partial | (UInt64(item.element) << UInt64(item.offset * 8))
    }
  }

  var speedKPH: Double? {
    guard feature.isSpeed, let rawValue else {
      return nil
    }

    return Double(rawValue) * 0.0036
  }
}

enum DragySPPProtocol {
  private static let block: [UInt8] = [0x0D, 0x0A, 0x0D, 0x0A]
  private static let frameCRC: UInt8 = 0xFB
  private static let readCommand: UInt8 = 0x01
  private static let dataAck: UInt8 = 0xAD
  private static let varType: [UInt8] = [0x20, 0x20, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]

  static func isSPPCharacteristic(uuid: String) -> Bool {
    let normalized = uuid.uppercased()
    return normalized == "FCFF" || normalized == "0000FCFF-0000-1000-8000-00805F9B34FB"
  }

  static func readFrame(for feature: DragySPPFeature) -> Data {
    let payload = [readCommand] + feature.address + varType
    return Data(block + [UInt8(payload.count + 1)] + payload + [frameCRC] + block)
  }

  static func parseReadResult(_ data: Data) -> DragySPPReadResult? {
    let bytes = Array(data)

    for frameBody in frameBodies(in: bytes) {
      guard frameBody.first == dataAck else {
        continue
      }

      let payload = Array(frameBody.dropFirst())
      if let result = parseReadPayload(payload) {
        return result
      }
    }

    return nil
  }

  private static func parseReadPayload(_ bytes: [UInt8]) -> DragySPPReadResult? {
    guard let valueLength = bytes.first.map(Int.init) else {
      return nil
    }

    let valueStart = 1
    let valueEnd = valueStart + valueLength
    let commandIndex = valueEnd + 1
    let featureStart = commandIndex + 1
    let featureEnd = featureStart + 8
    guard valueEnd <= bytes.count, featureEnd <= bytes.count, bytes[commandIndex] == readCommand else {
      return parseReadPayloadByFeatureScan(bytes)
    }

    let address = Array(bytes[featureStart..<featureEnd])
    guard let feature = DragySPPFeature.allCases.first(where: { $0.address == address }) else {
      return parseReadPayloadByFeatureScan(bytes)
    }

    return DragySPPReadResult(
      feature: feature,
      value: Data(bytes[valueStart..<valueEnd])
    )
  }

  private static func parseReadPayloadByFeatureScan(_ bytes: [UInt8]) -> DragySPPReadResult? {
    for feature in DragySPPFeature.allCases {
      guard let featureIndex = bytes.firstIndex(of: feature.address) else {
        continue
      }

      let valueEnd = featureIndex
      let valueStart = max(0, valueEnd - 8)
      let value = bytes[valueStart..<valueEnd].filter { $0 != readCommand && $0 != frameCRC }
      guard !value.isEmpty else {
        continue
      }

      return DragySPPReadResult(feature: feature, value: Data(value))
    }

    return nil
  }

  private static func frameBodies(in bytes: [UInt8]) -> [[UInt8]] {
    var bodies: [[UInt8]] = []
    var searchStart = 0

    while let frameStart = bytes.firstIndex(of: block, startingAt: searchStart) {
      let lengthIndex = frameStart + block.count
      let bodyStart = lengthIndex + 1
      guard bodyStart < bytes.count else {
        break
      }

      guard let frameEnd = bytes.firstIndex(of: block, startingAt: bodyStart) else {
        break
      }

      let bodyEnd = max(bodyStart, frameEnd - 1)
      bodies.append(Array(bytes[bodyStart..<bodyEnd]))
      searchStart = frameEnd + block.count
    }

    return bodies
  }
}

private extension [UInt8] {
  func firstIndex(of needle: [UInt8], startingAt start: Int = 0) -> Int? {
    guard !needle.isEmpty, count >= needle.count, start <= count - needle.count else {
      return nil
    }

    for index in start...(count - needle.count) {
      if Array(self[index..<(index + needle.count)]) == needle {
        return index
      }
    }

    return nil
  }
}
