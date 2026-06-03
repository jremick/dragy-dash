import Foundation

enum DragyDeviceStatusDecoder {
  static func batteryPercent(from data: Data) -> Int? {
    guard data.count >= 2 else {
      return nil
    }

    let percent = Int(data[data.startIndex + 1])
    guard (0...100).contains(percent) else {
      return nil
    }

    return percent
  }
}
