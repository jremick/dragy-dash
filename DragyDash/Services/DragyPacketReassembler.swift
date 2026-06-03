import Foundation

struct DragyPacketReassembler {
  private var buffers: [String: [UInt8]] = [:]

  mutating func reset() {
    buffers.removeAll()
  }

  mutating func packets(from data: Data, characteristicUUID: String) -> [Data] {
    guard characteristicUUID.uppercased() == "FD02" else {
      return [data]
    }

    buffers[characteristicUUID, default: []].append(contentsOf: data)
    return drainUBXPackets(for: characteristicUUID)
  }

  private mutating func drainUBXPackets(for characteristicUUID: String) -> [Data] {
    var packets: [Data] = []
    var buffer = buffers[characteristicUUID, default: []]

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

      packets.append(Data(buffer[0..<frameLength]))
      buffer.removeFirst(frameLength)
    }

    buffers[characteristicUUID] = buffer
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
}
