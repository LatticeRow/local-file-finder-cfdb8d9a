import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        TabView(selection: Binding(
            get: { container.appState.selectedTab },
            set: { container.appState.selectedTab = $0 }
        )) {
            NavigationStack {
                SearchScene(searchRepository: container.searchRepository)
            }
            .tabItem {
                Label("Search", systemImage: "sparkle.magnifyingglass")
            }
            .tag(RootTab.search)

            NavigationStack {
                SourceLibraryView()
            }
            .tabItem {
                Label("Library", systemImage: "books.vertical.fill")
            }
            .tag(RootTab.library)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "slider.horizontal.3")
            }
            .tag(RootTab.settings)
        }
        .toolbarBackground(AppTheme.canvas, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarColorScheme(.dark, for: .tabBar)
        .background(AppTheme.background.ignoresSafeArea())
    }
}

#Preview {
    RootView()
        .preferredColorScheme(.dark)
        .environment(AppContainer.preview())
        .modelContainer(AppContainer.makeModelContainer(inMemoryOnly: true))
}
