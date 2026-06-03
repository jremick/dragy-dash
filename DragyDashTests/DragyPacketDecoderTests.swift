import Foundation
import Testing
@testable import DragyDash

struct DragyPacketDecoderTests {
  @Test func decodesRMCSpeedInKnots() throws {
    let packet = "$GNRMC,092751.000,A,5321.6802,N,00630.3372,W,10.0,31.66,280511,,,A*43"
    let data = try #require(packet.data(using: .utf8))

    let snapshot = try #require(
      DragyPacketDecoder().decode(data, characteristicUUID: "test", sourceName: "Dragy Pro")
    )

    #expect(abs(snapshot.speedKPH - 18.52) < 0.01)
    #expect(abs(snapshot.speedMPH - 11.51) < 0.01)
    #expect(snapshot.headingDegrees == 31.66)
    #expect(snapshot.fixQuality == .threeD)
  }

  @Test func decodesGGAFixDetails() throws {
    let packet = "$GNGGA,092725.000,5321.6802,N,00630.3372,W,1,18,0.8,52.4,M,46.9,M,,*47"
    let data = try #require(packet.data(using: .utf8))

    let snapshot = try #require(
      DragyPacketDecoder().decode(data, characteristicUUID: "test", sourceName: "Dragy Pro")
    )

    #expect(abs((snapshot.latitude ?? 0) - 53.3613367) < 0.00001)
    #expect(abs((snapshot.longitude ?? 0) - -6.50562) < 0.00001)
    #expect(snapshot.satelliteCount == 18)
    #expect(snapshot.altitudeMeters == 52.4)
    #expect(snapshot.horizontalAccuracyMeters == 4.0)
    #expect(snapshot.fixQuality == .threeD)
  }

  @Test func decodesVTGSpeedInKPH() throws {
    let packet = "$GNVTG,31.66,T,,M,10.0,N,18.5,K,A*2C"
    let data = try #require(packet.data(using: .utf8))

    let snapshot = try #require(
      DragyPacketDecoder().decode(data, characteristicUUID: "test", sourceName: "Dragy Pro")
    )

    #expect(snapshot.speedKPH == 18.5)
    #expect(snapshot.headingDegrees == 31.66)
  }

  @Test func mergesMultipleNMEASentencesInOnePacket() throws {
    let packet = """
    $GNRMC,092751.000,A,5321.6802,N,00630.3372,W,10.0,31.66,280511,,,A*43
    $GNGGA,092725.000,5321.6802,N,00630.3372,W,1,18,0.8,52.4,M,46.9,M,,*47
    """
    let data = try #require(packet.data(using: .utf8))

    let snapshot = try #require(
      DragyPacketDecoder().decode(data, characteristicUUID: "test", sourceName: "Dragy Pro")
    )

    #expect(abs(snapshot.speedKPH - 18.52) < 0.01)
    #expect(snapshot.satelliteCount == 18)
    #expect(snapshot.altitudeMeters == 52.4)
  }

  @Test func ignoresUnknownBinaryPayload() {
    let data = Data([0x01, 0x02, 0x03, 0x04])
    let snapshot = DragyPacketDecoder().decode(data, characteristicUUID: "test", sourceName: "Dragy Pro")

    #expect(snapshot == nil)
  }

  @Test func decodesUBXNavPVT() throws {
    let data = makeUBXNavPVT(
      latitude: -37.8136,
      longitude: 144.9631,
      altitudeMillimeters: 51_200,
      groundSpeedMillimetersPerSecond: 10_000,
      headingScaled: 9_000_000,
      horizontalAccuracyMillimeters: 900,
      fixType: 3,
      satelliteCount: 18
    )

    let snapshot = try #require(
      DragyPacketDecoder().decode(data, characteristicUUID: "FD02", sourceName: "Dragy Pro")
    )

    #expect(abs(snapshot.speedKPH - 36.0) < 0.001)
    #expect(abs((snapshot.latitude ?? 0) - -37.8136) < 0.000001)
    #expect(abs((snapshot.longitude ?? 0) - 144.9631) < 0.000001)
    #expect(snapshot.altitudeMeters == 51.2)
    #expect(snapshot.horizontalAccuracyMeters == 0.9)
    #expect(abs((snapshot.headingDegrees ?? 0) - 90) < 0.001)
    #expect(snapshot.satelliteCount == 18)
    #expect(snapshot.fixQuality == .threeD)
  }

  @Test func reassemblesFragmentedUBXNavPVT() throws {
    let data = makeUBXNavPVT(
      latitude: -37.8136,
      longitude: 144.9631,
      altitudeMillimeters: 51_200,
      groundSpeedMillimetersPerSecond: 10_000,
      headingScaled: 9_000_000,
      horizontalAccuracyMillimeters: 900,
      fixType: 3,
      satelliteCount: 18
    )
    var reassembler = DragyPacketReassembler()
    var packets: [Data] = []

    var offset = 0
    while offset < data.count {
      let end = min(data.count, offset + 14)
      packets.append(contentsOf: reassembler.packets(
        from: data.subdata(in: offset..<end),
        characteristicUUID: "FD02"
      ))
      offset = end
    }

    #expect(packets == [data])
    let firstPacket = try #require(packets.first)
    let snapshot = try #require(
      DragyPacketDecoder().decode(firstPacket, characteristicUUID: "FD02", sourceName: "Dragy Pro")
    )
    #expect(abs(snapshot.speedKPH - 36.0) < 0.001)
  }

  @Test func zerosUBXSpeedWithoutUsableFix() throws {
    let data = makeUBXNavPVT(
      latitude: -37.8136,
      longitude: 144.9631,
      altitudeMillimeters: 51_200,
      groundSpeedMillimetersPerSecond: 10_000,
      headingScaled: 9_000_000,
      horizontalAccuracyMillimeters: 900,
      fixType: 0,
      satelliteCount: 0
    )

    let snapshot = try #require(
      DragyPacketDecoder().decode(data, characteristicUUID: "FD02", sourceName: "Dragy Pro")
    )

    #expect(snapshot.speedKPH == 0)
    #expect(snapshot.fixQuality == .none)
  }
}

private func makeUBXNavPVT(
  latitude: Double,
  longitude: Double,
  altitudeMillimeters: Int32,
  groundSpeedMillimetersPerSecond: Int32,
  headingScaled: Int32,
  horizontalAccuracyMillimeters: UInt32,
  fixType: UInt8,
  satelliteCount: UInt8
) -> Data {
  var payload = [UInt8](repeating: 0, count: 92)
  writeUInt32LE(123_456, into: &payload, at: 0)
  writeUInt16LE(2026, into: &payload, at: 4)
  payload[6] = 6
  payload[7] = 3
  payload[8] = 12
  payload[9] = 34
  payload[10] = 56
  payload[20] = fixType
  payload[23] = satelliteCount
  writeInt32LE(Int32((longitude * 10_000_000).rounded()), into: &payload, at: 24)
  writeInt32LE(Int32((latitude * 10_000_000).rounded()), into: &payload, at: 28)
  writeInt32LE(altitudeMillimeters, into: &payload, at: 36)
  writeUInt32LE(horizontalAccuracyMillimeters, into: &payload, at: 40)
  writeInt32LE(groundSpeedMillimetersPerSecond, into: &payload, at: 60)
  writeInt32LE(headingScaled, into: &payload, at: 64)

  var message: [UInt8] = [0x01, 0x07, 0x5C, 0x00] + payload
  let checksum = ubxChecksum(message)
  message.append(contentsOf: checksum)
  return Data([0xB5, 0x62] + message)
}

private func ubxChecksum(_ bytes: [UInt8]) -> [UInt8] {
  var checksumA: UInt8 = 0
  var checksumB: UInt8 = 0

  for byte in bytes {
    checksumA &+= byte
    checksumB &+= checksumA
  }

  return [checksumA, checksumB]
}

private func writeUInt16LE(_ value: UInt16, into bytes: inout [UInt8], at offset: Int) {
  bytes[offset] = UInt8(value & 0x00FF)
  bytes[offset + 1] = UInt8((value >> 8) & 0x00FF)
}

private func writeUInt32LE(_ value: UInt32, into bytes: inout [UInt8], at offset: Int) {
  bytes[offset] = UInt8(value & 0x000000FF)
  bytes[offset + 1] = UInt8((value >> 8) & 0x000000FF)
  bytes[offset + 2] = UInt8((value >> 16) & 0x000000FF)
  bytes[offset + 3] = UInt8((value >> 24) & 0x000000FF)
}

private func writeInt32LE(_ value: Int32, into bytes: inout [UInt8], at offset: Int) {
  writeUInt32LE(UInt32(bitPattern: value), into: &bytes, at: offset)
}
