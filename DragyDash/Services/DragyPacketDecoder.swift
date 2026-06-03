import Foundation

struct DragyPacketDecoder {
  func decode(_ data: Data, characteristicUUID: String, sourceName: String) -> TelemetrySnapshot? {
    if let snapshot = decodeUBXNavPVT(data, sourceName: sourceName) {
      return snapshot
    }

    if let sppResult = DragySPPProtocol.parseReadResult(data), let speedKPH = sppResult.speedKPH {
      return TelemetrySnapshot(
        timestamp: .now,
        speedKPH: speedKPH,
        headingDegrees: nil,
        altitudeMeters: nil,
        horizontalAccuracyMeters: nil,
        satelliteCount: nil,
        fixQuality: .none,
        longitudinalG: nil,
        lateralG: nil,
        verticalG: nil,
        yawRateDegreesPerSecond: nil,
        sourceName: "\(sourceName) SPP"
      )
    }

    guard let ascii = String(data: data, encoding: .utf8) else {
      return nil
    }

    var partial = NMEAPartial(sourceName: sourceName)
    let sentences = ascii
      .components(separatedBy: CharacterSet.newlines)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }

    for sentence in sentences {
      decodeNMEASentence(sentence, into: &partial)
    }

    guard partial.hasData else {
      return nil
    }

    return partial.snapshot()
  }

  private func decodeNMEASentence(_ sentence: String, into partial: inout NMEAPartial) {
    let fields = sentence.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
    guard let type = fields.first?.suffix(3) else {
      return
    }

    switch type {
    case "RMC":
      decodeRMC(fields, into: &partial)
    case "GGA":
      decodeGGA(fields, into: &partial)
    case "VTG":
      decodeVTG(fields, into: &partial)
    default:
      return
    }
  }

  private func decodeRMC(_ fields: [String], into partial: inout NMEAPartial) {
    guard fields.count > 8 else {
      return
    }

    partial.hasData = true
    let status = fields[2]
    guard status == "A" else {
      partial.speedKPH = 0
      partial.fixQuality = FixQuality.none
      return
    }

    let speedKnots = clean(fields[7]).flatMap(Double.init) ?? 0
    partial.speedKPH = speedKnots * 1.852
    partial.headingDegrees = clean(fields[8]).flatMap(Double.init)
    partial.latitude = coordinate(value: fields[3], hemisphere: fields[4])
    partial.longitude = coordinate(value: fields[5], hemisphere: fields[6])
    partial.fixQuality = .threeD
  }

  private func decodeGGA(_ fields: [String], into partial: inout NMEAPartial) {
    guard fields.count > 9 else {
      return
    }

    partial.hasData = true
    partial.latitude = partial.latitude ?? coordinate(value: fields[2], hemisphere: fields[3])
    partial.longitude = partial.longitude ?? coordinate(value: fields[4], hemisphere: fields[5])

    let fixCode = clean(fields[6]).flatMap(Int.init) ?? 0
    partial.fixQuality = fixQuality(forGGAQualityCode: fixCode)
    partial.satelliteCount = clean(fields[7]).flatMap(Int.init)
    if let hdop = clean(fields[8]).flatMap(Double.init) {
      partial.horizontalAccuracyMeters = hdop * 5
    }
    partial.altitudeMeters = clean(fields[9]).flatMap(Double.init)
  }

  private func decodeVTG(_ fields: [String], into partial: inout NMEAPartial) {
    guard fields.count > 7 else {
      return
    }

    partial.hasData = true
    partial.headingDegrees = clean(fields[1]).flatMap(Double.init)
    partial.speedKPH = clean(fields[7]).flatMap(Double.init)
    if partial.speedKPH == nil, let speedKnots = clean(fields[5]).flatMap(Double.init) {
      partial.speedKPH = speedKnots * 1.852
    }
    if partial.fixQuality == nil {
      partial.fixQuality = .threeD
    }
  }

  private func coordinate(value: String, hemisphere: String) -> Double? {
    guard let cleaned = clean(value), !cleaned.isEmpty else {
      return nil
    }

    let hemisphere = clean(hemisphere) ?? ""
    let degreeDigits = hemisphere == "E" || hemisphere == "W" ? 3 : 2
    guard cleaned.count > degreeDigits else {
      return nil
    }

    let degreeText = String(cleaned.prefix(degreeDigits))
    let minuteText = String(cleaned.dropFirst(degreeDigits))
    guard let degrees = Double(degreeText), let minutes = Double(minuteText) else {
      return nil
    }

    let sign = hemisphere == "S" || hemisphere == "W" ? -1.0 : 1.0
    return sign * (degrees + minutes / 60)
  }

  private func fixQuality(forGGAQualityCode code: Int) -> FixQuality {
    switch code {
    case 0:
      .none
    case 6:
      .estimated
    default:
      .threeD
    }
  }

  private func clean(_ field: String) -> String? {
    let stripped = field.split(separator: "*", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? field
    let trimmed = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private func decodeUBXNavPVT(_ data: Data, sourceName: String) -> TelemetrySnapshot? {
    let bytes = Array(data)
    guard bytes.count >= 98 else {
      return nil
    }

    for index in bytes.indices {
      if index + 6 <= bytes.count,
         bytes[index] == 0xB5,
         bytes[index + 1] == 0x62,
         let snapshot = parseUBXNavPVT(bytes, messageStart: index + 2, sourceName: sourceName) {
        return snapshot
      }

      if index + 4 <= bytes.count,
         bytes[index] == 0x01,
         bytes[index + 1] == 0x07,
         let snapshot = parseUBXNavPVT(bytes, messageStart: index, sourceName: sourceName) {
        return snapshot
      }
    }

    return nil
  }

  private func parseUBXNavPVT(_ bytes: [UInt8], messageStart: Int, sourceName: String) -> TelemetrySnapshot? {
    let headerLength = 4
    guard messageStart + headerLength <= bytes.count,
          bytes[messageStart] == 0x01,
          bytes[messageStart + 1] == 0x07 else {
      return nil
    }

    let payloadLength = Int(u16LE(bytes, messageStart + 2))
    guard payloadLength == 92 else {
      return nil
    }

    let payloadStart = messageStart + headerLength
    let checksumIndex = payloadStart + payloadLength
    guard checksumIndex + 2 <= bytes.count, validateUBXChecksum(bytes, start: messageStart, end: checksumIndex) else {
      return nil
    }

    let fixType = Int(bytes[payloadStart + 20])
    let satelliteCount = Int(bytes[payloadStart + 23])
    let longitude = Double(i32LE(bytes, payloadStart + 24)) / 10_000_000
    let latitude = Double(i32LE(bytes, payloadStart + 28)) / 10_000_000
    let altitudeMeters = Double(i32LE(bytes, payloadStart + 36)) / 1000
    let horizontalAccuracyMeters = Double(u32LE(bytes, payloadStart + 40)) / 1000
    let fixQuality = fixQuality(forUBXFixType: fixType)
    let decodedSpeedKPH = max(0, Double(i32LE(bytes, payloadStart + 60)) * 3.6 / 1000)
    let speedKPH = fixQuality == .none ? 0 : decodedSpeedKPH
    let headingDegrees = Double(i32LE(bytes, payloadStart + 64)) * 0.00001

    return TelemetrySnapshot(
      timestamp: .now,
      speedKPH: speedKPH,
      headingDegrees: headingDegrees,
      latitude: latitude,
      longitude: longitude,
      altitudeMeters: altitudeMeters,
      horizontalAccuracyMeters: horizontalAccuracyMeters,
      satelliteCount: satelliteCount,
      fixQuality: fixQuality,
      longitudinalG: nil,
      lateralG: nil,
      verticalG: nil,
      yawRateDegreesPerSecond: nil,
      sourceName: "\(sourceName) UBX"
    )
  }

  private func fixQuality(forUBXFixType fixType: Int) -> FixQuality {
    switch fixType {
    case 0, 1:
      .none
    case 2:
      .twoD
    case 3, 4:
      .threeD
    default:
      .estimated
    }
  }

  private func validateUBXChecksum(_ bytes: [UInt8], start: Int, end: Int) -> Bool {
    var checksumA: UInt8 = 0
    var checksumB: UInt8 = 0

    for byte in bytes[start..<end] {
      checksumA &+= byte
      checksumB &+= checksumA
    }

    return checksumA == bytes[end] && checksumB == bytes[end + 1]
  }

  private func u16LE(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
    UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
  }

  private func u32LE(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
    UInt32(bytes[offset])
      | (UInt32(bytes[offset + 1]) << 8)
      | (UInt32(bytes[offset + 2]) << 16)
      | (UInt32(bytes[offset + 3]) << 24)
  }

  private func i32LE(_ bytes: [UInt8], _ offset: Int) -> Int32 {
    Int32(bitPattern: u32LE(bytes, offset))
  }
}

private struct NMEAPartial {
  var sourceName: String
  var hasData = false
  var speedKPH: Double?
  var headingDegrees: Double?
  var latitude: Double?
  var longitude: Double?
  var altitudeMeters: Double?
  var horizontalAccuracyMeters: Double?
  var satelliteCount: Int?
  var fixQuality: FixQuality?

  func snapshot() -> TelemetrySnapshot {
    TelemetrySnapshot(
      timestamp: .now,
      speedKPH: speedKPH ?? 0,
      headingDegrees: headingDegrees,
      latitude: latitude,
      longitude: longitude,
      altitudeMeters: altitudeMeters,
      horizontalAccuracyMeters: horizontalAccuracyMeters,
      satelliteCount: satelliteCount,
      fixQuality: fixQuality ?? .none,
      longitudinalG: nil,
      lateralG: nil,
      verticalG: nil,
      yawRateDegreesPerSecond: nil,
      sourceName: sourceName
    )
  }
}

extension Data {
  var hexString: String {
    map { String(format: "%02X", $0) }.joined(separator: " ")
  }

  var asciiPreview: String? {
    guard let text = String(data: self, encoding: .utf8) else {
      return nil
    }

    let filtered = text
      .replacingOccurrences(of: "\r", with: " ")
      .replacingOccurrences(of: "\n", with: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return filtered.isEmpty ? nil : filtered
  }
}
