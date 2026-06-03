import SwiftUI

@main
struct DragyDashApp: App {
  @StateObject private var store = TelemetryStore()

  var body: some Scene {
    WindowGroup {
      AppView(store: store)
    }
  }
}

