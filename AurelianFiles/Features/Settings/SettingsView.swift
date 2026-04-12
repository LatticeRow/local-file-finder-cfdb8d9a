import SwiftUI

struct SettingsView: View {
    private let diagnostics = [
        "SwiftData container is centralized in AppContainer.",
        "Bookmark, indexing, extraction, preview, and search services are constructed in one place.",
        "No network services are configured in this shell.",
    ]

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Settings")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(AppTheme.primaryText)

                    Text("Maintenance and diagnostics placeholders for the local-first app shell.")
                        .foregroundStyle(AppTheme.secondaryText)

                    VStack(alignment: .leading, spacing: 12) {
                        Button("Manual Full Reindex") {}
                            .buttonStyle(.borderedProminent)
                        Button("Clear Local Index", role: .destructive) {}
                            .buttonStyle(.bordered)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Diagnostics")
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
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .preferredColorScheme(.dark)
}
