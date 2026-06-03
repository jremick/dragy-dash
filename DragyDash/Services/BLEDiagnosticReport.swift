import Foundation

struct BLEDiagnosticReport {
  static func make(
    status: BluetoothStatus,
    diagnostics: BLEDiagnostics,
    telemetry: TelemetrySnapshot,
    batteryPercent: Int?
  ) -> String {
    var lines: [String] = []
    lines.append("DragyDash BLE Diagnostic Report")
    lines.append("Generated: \(DragyDateFormatter.string(from: .now))")
    lines.append("Status: \(status.label)")
    lines.append("Telemetry Source: \(telemetry.sourceName)")
    lines.append("Speed: \(String(format: "%.2f", telemetry.speedKPH)) km/h")
    if let batteryPercent {
      lines.append("Battery: \(batteryPercent)%")
    }
    lines.append("Fix: \(telemetry.fixQuality.rawValue)")
    lines.append("Coordinate: \(telemetry.coordinateLabel)")
    lines.append("")

    lines.append("Events (\(diagnostics.events.count))")
    for event in diagnostics.events {
      lines.append("- \(DragyDateFormatter.string(from: event.timestamp)) \(event.message)")
    }
    lines.append("")

    lines.append("Devices (\(diagnostics.devices.count))")
    for device in diagnostics.devices {
      lines.append("- \(device.name) [\(device.id.uuidString)]")
      lines.append("  RSSI: \(device.rssi)")
      lines.append("  Dragy Candidate: \(device.isDragyCandidate ? "yes" : "no")")
      if let localName = device.localName {
        lines.append("  Local Name: \(localName)")
      }
      if let manufacturerDataHex = device.manufacturerDataHex {
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
        lines.append("  Value: \(valueDescription)")
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
      lines.append("  HEX: \(packet.hex)")
      if let asciiPreview = packet.asciiPreview {
        lines.append("  ASCII: \(asciiPreview)")
      }
    }

    return lines.joined(separator: "\n")
  }
}
