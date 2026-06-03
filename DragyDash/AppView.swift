import SwiftUI

struct AppView: View {
  @ObservedObject var store: TelemetryStore

  var body: some View {
    DashboardView(store: store)
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
