import Foundation

struct DragyPacketReassembler: Sendable {
  private static let maxBufferBytes = 8_192
  private var buffers: [String: [UInt8]] = [:]

  mutating func reset() {
    buffers.removeAll()
  }

  mutating func packets(from data: Data, characteristicUUID: String) -> [Data] {
    guard let key = canonicalStreamKey(for: characteristicUUID) else {
      return [data]
    }

    var buffer = buffers[key, default: []]
    buffer.append(contentsOf: data)
    if buffer.count > Self.maxBufferBytes {
      buffer.removeFirst(buffer.count - Self.maxBufferBytes)
    }

    let packets = drainUBXPackets(from: &buffer)
    buffers[key] = buffer
    return packets
  }

  private func canonicalStreamKey(for characteristicUUID: String) -> String? {
    let normalized = characteristicUUID.uppercased()
    if normalized == "FD02" || normalized == "0000FD02-0000-1000-8000-00805F9B34FB" {
      return "FD02"
    }
    return nil
  }

  private func drainUBXPackets(from buffer: inout [UInt8]) -> [Data] {
    var packets: [Data] = []

    while true {
      guard let syncIndex = buffer.firstSyncIndex() else {
        if buffer.count > 1 {
          buffer = Array(buffer.suffix(1))
        }
        break
      }

      if syncIndex > 0 {
        buffer.removeFirst(syncIndex)
      }

      guard buffer.count >= 6 else {
        break
      }

      let payloadLength = Int(buffer[4]) | (Int(buffer[5]) << 8)
      let frameLength = 6 + payloadLength + 2
      guard frameLength <= 1024 else {
        buffer.removeFirst(2)
        continue
      }

      guard buffer.count >= frameLength else {
        break
      }

      if buffer.hasValidUBXChecksum(frameLength: frameLength) {
        packets.append(Data(buffer[0..<frameLength]))
        buffer.removeFirst(frameLength)
      } else {
        // False sync or corrupted frame: advance past the 2-byte sync marker
        // so any valid UBX frame embedded inside the payload bytes is preserved.
        buffer.removeFirst(2)
      }
    }

    return packets
  }
}

private extension [UInt8] {
  func firstSyncIndex() -> Int? {
    guard count >= 2 else {
      return nil
    }

    for index in 0..<(count - 1) {
      if self[index] == 0xB5, self[index + 1] == 0x62 {
        return index
      }
    }

    return nil
  }

  func hasValidUBXChecksum(frameLength: Int) -> Bool {
    guard frameLength >= 8, count >= frameLength else {
      return false
    }

    var checksumA: UInt8 = 0
    var checksumB: UInt8 = 0
    for index in 2..<(frameLength - 2) {
      checksumA &+= self[index]
      checksumB &+= checksumA
    }

    return checksumA == self[frameLength - 2] && checksumB == self[frameLength - 1]
  }
}
