import Foundation
import Testing
@testable import DragyDash

struct DragyDeviceStatusDecoderTests {
  @Test func decodesBatteryPercentFromSecondDeviceStatusByte() {
    #expect(DragyDeviceStatusDecoder.batteryPercent(from: Data([0x01, 0x54])) == 84)
  }

  @Test func rejectsShortOrOutOfRangeDeviceStatus() {
    #expect(DragyDeviceStatusDecoder.batteryPercent(from: Data([0x01])) == nil)
    #expect(DragyDeviceStatusDecoder.batteryPercent(from: Data([0x01, 0xFE])) == nil)
  }
}
