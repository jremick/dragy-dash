import Foundation
import Testing
@testable import DragyDash

struct SavedSessionStoreTests {
  @Test func savesOnlyNewestThreeSessions() throws {
    let directoryURL = temporaryDirectory()
    let store = SavedSessionStore(directoryURL: directoryURL)
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    for index in 0..<5 {
      _ = try store.save(
        csv: "timestamp,speed_kph\n\(index),\(index)",
        at: start.addingTimeInterval(Double(index))
      )
    }

    let sessions = store.loadSessions()
    #expect(sessions.count == 3)
    #expect(sessions.map(\.createdAt) == [
      start.addingTimeInterval(4),
      start.addingTimeInterval(3),
      start.addingTimeInterval(2)
    ])
    #expect((try FileManager.default.contentsOfDirectory(atPath: directoryURL.path)).count == 3)
  }

  @Test func clearsSavedSessions() throws {
    let directoryURL = temporaryDirectory()
    let store = SavedSessionStore(directoryURL: directoryURL)

    _ = try store.save(csv: "timestamp,speed_kph\n1,100")
    try store.clear()

    #expect(store.loadSessions().isEmpty)
  }

  @Test func persistsSavingToggle() throws {
    let defaults = try #require(UserDefaults(suiteName: "DragyDashTests-\(UUID().uuidString)"))
    let directoryURL = temporaryDirectory()
    let firstStore = SavedSessionStore(directoryURL: directoryURL, defaults: defaults)

    #expect(firstStore.isSavingEnabled)
    firstStore.setSavingEnabled(false)

    let secondStore = SavedSessionStore(directoryURL: directoryURL, defaults: defaults)
    #expect(!secondStore.isSavingEnabled)
  }

  private func temporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("DragyDashTests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
}
