import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.modelContext) private var modelContext

    @State private var showingClearConfirmation = false
    @State private var clearErrorMessage: String?

    private let diagnostics = [
        "Search stays on this iPhone.",
        "You can reindex your library at any time.",
        "Clearing removes saved access and search data.",
    ]

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Settings")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(AppTheme.primaryText)

                    Text("Manage your search library.")
                        .foregroundStyle(AppTheme.secondaryText)

                    VStack(alignment: .leading, spacing: 12) {
                        Button("Manual Full Reindex") {
                            runFullReindex()
                        }
                            .buttonStyle(.borderedProminent)
                            .disabled(container.appState.isIndexing)
                        Button("Clear Local Library", role: .destructive) {
                            showingClearConfirmation = true
                        }
                            .buttonStyle(.bordered)
                            .disabled(container.appState.isIndexing)
                    }

                    if container.appState.isIndexing || container.appState.indexingDetail != nil {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(container.appState.indexingSummary)
                                .foregroundStyle(AppTheme.primaryText)

                            if let detail = container.appState.indexingDetail {
                                Text(detail)
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.secondaryText)
                                    .lineLimit(1)
                            }
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(AppTheme.cardBorder, lineWidth: 1)
                        )
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("About")
                            .font(.headline)
                            .foregroundStyle(AppTheme.primaryText)

                        ForEach(diagnostics, id: \.self) { line in
                            Label(line, systemImage: "checkmark.seal")
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(AppTheme.cardBorder, lineWidth: 1)
                    )
                }
                .padding(20)
            }
            .safeAreaPadding(.bottom, AppTheme.tabBarContentInset)
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .alert("Clear Local Library?", isPresented: $showingClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                clearLocalLibrary()
            }
        } message: {
            Text("This removes saved source bookmarks and any local index data stored by the app.")
        }
        .alert(
            "Clear Failed",
            isPresented: Binding(
                get: { clearErrorMessage != nil },
                set: { if !$0 { clearErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(clearErrorMessage ?? "Unknown error.")
        }
    }

    private func clearLocalLibrary() {
        do {
            let files = try modelContext.fetch(FetchDescriptor<IndexedFile>())
            let extractedContent = try modelContext.fetch(FetchDescriptor<ExtractedContent>())
            let jobs = try modelContext.fetch(FetchDescriptor<IndexingJob>())
            let sources = try modelContext.fetch(FetchDescriptor<IndexedSource>())

            for file in files {
                if let thumbnailPath = file.thumbnailPath {
                    try? FileManager.default.removeItem(atPath: thumbnailPath)
                }
                modelContext.delete(file)
            }

            for chunk in extractedContent {
                modelContext.delete(chunk)
            }

            for job in jobs {
                modelContext.delete(job)
            }

            for source in sources {
                modelContext.delete(source)
            }

            try modelContext.save()
        } catch {
            clearErrorMessage = "Try again in a moment."
        }
    }

    private func runFullReindex() {
        container.indexingCoordinator.runReindexAllSources()
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .preferredColorScheme(.dark)
}
