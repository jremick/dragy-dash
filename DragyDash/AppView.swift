import SwiftUI

struct AppView: View {
  var store: TelemetryStore

  var body: some View {
    DashboardView(store: store)
      .onOpenURL { _ in
        // Deep links from the Dynamic Island / Live Activity foreground the dashboard.
      }
      .task {
        #if targetEnvironment(simulator)
        store.startMockTelemetry()
        #else
        store.setSourceMode(.bluetooth)
        #endif
      }
  }
}

#Preview {
  AppView(store: TelemetryStore.preview)
}
