import Foundation

struct BLEDiagnosticReport {
  static func make(
    status: BluetoothStatus,
    diagnostics: BLEDiagnostics,
    telemetry: TelemetrySnapshot,
    batteryPercent: Int?,
    redacted: Bool = true
  ) -> String {
    var lines: [String] = []
    lines.append("DragyDash BLE Diagnostic Report\(redacted ? " (Redacted)" : "")")
    lines.append("Generated: \(DragyDateFormatter.string(from: .now))")
    lines.append("Status: \(redacted ? redactDeviceIdentifiers(in: status.label) : status.label)")
    lines.append("Telemetry Source: \(redacted ? redactDeviceIdentifiers(in: telemetry.sourceName) : telemetry.sourceName)")
    lines.append("Speed: \(String(format: "%.2f", telemetry.speedKPH)) km/h")
    if let batteryPercent {
      lines.append("Battery: \(batteryPercent)%")
    }
    lines.append("Fix: \(telemetry.fixQuality.rawValue)")
    if redacted {
      let hasCoords = telemetry.latitude != nil && telemetry.longitude != nil
      lines.append("Coordinate: \(hasCoords ? "[redacted]" : "--")")
    } else {
      lines.append("Coordinate: \(telemetry.coordinateLabel)")
    }
    lines.append("")

    lines.append("Events (\(diagnostics.events.count))")
    for event in diagnostics.events {
      let message = redacted ? redactDeviceIdentifiers(in: event.message) : event.message
      lines.append("- \(DragyDateFormatter.string(from: event.timestamp)) \(message)")
    }
    lines.append("")

    let visibleDevices = redacted ? diagnostics.devices.filter(\.isDragyCandidate) : diagnostics.devices
    lines.append("Devices (\(visibleDevices.count))")
    for device in visibleDevices {
      let name = redacted ? redactDeviceIdentifiers(in: device.name) : device.name
      let id = redacted ? "[redacted-uuid]" : device.id.uuidString
      lines.append("- \(name) [\(id)]")
      lines.append("  RSSI: \(device.rssi)")
      lines.append("  Dragy Candidate: \(device.isDragyCandidate ? "yes" : "no")")
      if let localName = device.localName {
        lines.append("  Local Name: \(redacted ? redactDeviceIdentifiers(in: localName) : localName)")
      }
      if !redacted, let manufacturerDataHex = device.manufacturerDataHex {
        lines.append("  Manufacturer Data: \(manufacturerDataHex)")
      }
      if !device.advertisedServiceUUIDs.isEmpty {
        lines.append("  Advertised Services: \(device.advertisedServiceUUIDs.joined(separator: ", "))")
      }
    }
    lines.append("")

    lines.append("Characteristics (\(diagnostics.characteristics.count))")
    for characteristic in diagnostics.characteristics {
      lines.append("- Service \(characteristic.serviceUUID)")
      lines.append("  Characteristic: \(characteristic.characteristicUUID)")
      lines.append("  Properties: \(characteristic.properties.joined(separator: ", "))")
    }
    lines.append("")

    lines.append("Descriptors (\(diagnostics.descriptors.count))")
    for descriptor in diagnostics.descriptors {
      lines.append("- Service \(descriptor.serviceUUID)")
      lines.append("  Characteristic: \(descriptor.characteristicUUID)")
      lines.append("  Descriptor: \(descriptor.descriptorUUID)")
      if let valueDescription = descriptor.valueDescription {
        lines.append("  Value: \(redacted ? redactDeviceIdentifiers(in: valueDescription) : valueDescription)")
      }
    }
    lines.append("")

    lines.append("Write Targets (\(diagnostics.writeTargets.count))")
    for target in diagnostics.writeTargets {
      lines.append("- \(target.displayName)")
      lines.append("  Service: \(target.serviceUUID)")
      lines.append("  Characteristic: \(target.characteristicUUID)")
      lines.append("  Properties: \(target.properties.joined(separator: ", "))")
    }
    lines.append("")

    lines.append("Packet Samples (\(diagnostics.packetSamples.count))")
    for packet in diagnostics.packetSamples {
      lines.append("- \(DragyDateFormatter.string(from: packet.timestamp)) \(packet.characteristicUUID)")
      if redacted && packet.characteristicUUID.uppercased().contains("FD02") {
        lines.append("  HEX: [redacted GNSS payload]")
      } else {
        lines.append("  HEX: \(packet.hex)")
        if let asciiPreview = packet.asciiPreview {
          lines.append("  ASCII: \(redacted ? redactDeviceIdentifiers(in: asciiPreview) : asciiPreview)")
        }
      }
    }

    return lines.joined(separator: "\n")
  }

  static func redactDeviceIdentifiers(in text: String) -> String {
    var result = text
    // Mask Dragy serial suffixes such as DRG70-123ABC -> DRG70-******
    result = result.replacingOccurrences(
      of: #"(?i)\b(DRG\d{0,3})-[A-Z0-9]{2,}\b"#,
      with: "$1-******",
      options: .regularExpression
    )
    // Mask standard UUIDs such as CoreBluetooth peripheral identifiers
    result = result.replacingOccurrences(
      of: #"(?i)\b[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}\b"#,
      with: "[redacted-uuid]",
      options: .regularExpression
    )
    return result
  }
}
