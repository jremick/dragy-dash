import SwiftUI

@main
struct DragyDashApp: App {
  @State private var store = TelemetryStore()

  var body: some Scene {
    WindowGroup {
      AppView(store: store)
    }
  }
}

