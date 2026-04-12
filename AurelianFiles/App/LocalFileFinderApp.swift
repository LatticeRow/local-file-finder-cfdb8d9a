import SwiftUI

@main
struct AurelianFilesApp: App {
    @State private var container = AppContainer.live()

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .environment(container)
                .modelContainer(container.modelContainer)
        }
    }
}
