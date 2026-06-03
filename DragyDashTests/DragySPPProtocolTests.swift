import Foundation
import Testing
@testable import DragyDash

struct DragySPPProtocolTests {
  @Test func buildsCurrentSpeedReadFrame() {
    let frame = DragySPPProtocol.readFrame(for: .currentSpeed)

    #expect(frame.hexString == "0D 0A 0D 0A 12 01 00 00 00 00 00 20 7C 84 20 20 00 00 00 00 00 00 FB 0D 0A 0D 0A")
  }

  @Test func parsesCurrentSpeedReadResult() throws {
    let value: [UInt8] = [0x10, 0x27, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
    let payload: [UInt8] = [0xAD, UInt8(value.count)] + value + [0x00, 0x01] + DragySPPFeature.currentSpeed.address
    let frame = Data([0x0D, 0x0A, 0x0D, 0x0A] + [UInt8(payload.count + 1)] + payload + [0xFB] + [0x0D, 0x0A, 0x0D, 0x0A])

    let result = try #require(DragySPPProtocol.parseReadResult(frame))

    #expect(result.feature == .currentSpeed)
    #expect(result.rawValue == 10_000)
    #expect(abs((result.speedKPH ?? 0) - 36.0) < 0.001)
  }
}
