import Foundation

struct SavedTelemetrySession: Equatable, Identifiable {
  let url: URL
  let createdAt: Date
  let byteCount: Int

  var id: String {
    url.lastPathComponent
  }
}

final class SavedSessionStore {
  private let fileManager: FileManager
  private let defaults: UserDefaults
  private let directoryURL: URL
  private let maxSavedSessions: Int
  private let isSavingEnabledKey = "dragyDash.isSessionSavingEnabled"

  init(
    directoryURL: URL? = nil,
    fileManager: FileManager = .default,
    defaults: UserDefaults = .standard,
    maxSavedSessions: Int = 3
  ) {
    self.fileManager = fileManager
    self.defaults = defaults
    self.maxSavedSessions = maxSavedSessions
    self.directoryURL = directoryURL ?? fileManager
      .urls(for: .documentDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Sessions", isDirectory: true)
  }

  var isSavingEnabled: Bool {
    guard defaults.object(forKey: isSavingEnabledKey) != nil else {
      return true
    }
    return defaults.bool(forKey: isSavingEnabledKey)
  }

  func setSavingEnabled(_ enabled: Bool) {
    defaults.set(enabled, forKey: isSavingEnabledKey)
  }

  func save(csv: String, at date: Date = .now) throws -> [SavedTelemetrySession] {
    try ensureDirectoryExists()

    let fileName = "dragydash-session-\(Self.fileTimestampString(from: date))-\(UUID().uuidString.prefix(6)).csv"
    let url = directoryURL.appendingPathComponent(fileName)
    try csv.write(to: url, atomically: true, encoding: .utf8)
    try fileManager.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    return try pruneAndLoadSessions()
  }

  func loadSessions() -> [SavedTelemetrySession] {
    (try? pruneAndLoadSessions()) ?? []
  }

  func clear() throws {
    guard fileManager.fileExists(atPath: directoryURL.path) else {
      return
    }

    let urls = try fileManager.contentsOfDirectory(
      at: directoryURL,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    )

    for url in urls where url.pathExtension.lowercased() == "csv" {
      try fileManager.removeItem(at: url)
    }
  }

  private func ensureDirectoryExists() throws {
    try fileManager.createDirectory(
      at: directoryURL,
      withIntermediateDirectories: true
    )
  }

  private func pruneAndLoadSessions() throws -> [SavedTelemetrySession] {
    guard fileManager.fileExists(atPath: directoryURL.path) else {
      return []
    }

    let urls = try fileManager.contentsOfDirectory(
      at: directoryURL,
      includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
      options: [.skipsHiddenFiles]
    )
    .filter { $0.pathExtension.lowercased() == "csv" }

    let sessions = urls
      .compactMap(session(from:))
      .sorted { $0.createdAt > $1.createdAt }

    for session in sessions.dropFirst(maxSavedSessions) {
      try fileManager.removeItem(at: session.url)
    }

    return Array(sessions.prefix(maxSavedSessions))
  }

  private func session(from url: URL) -> SavedTelemetrySession? {
    guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) else {
      return nil
    }

    return SavedTelemetrySession(
      url: url,
      createdAt: values.contentModificationDate ?? .distantPast,
      byteCount: values.fileSize ?? 0
    )
  }

  private static func fileTimestampString(from date: Date) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return formatter.string(from: date)
  }
}
