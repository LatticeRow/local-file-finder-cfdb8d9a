import SwiftUI

struct SourceLibraryView: View {
    private let placeholderSources: [LibrarySourceCardModel] = [
        .init(name: "Added sources", detail: "Bookmark-backed folders and files will appear here.", status: "Ready"),
        .init(name: "Last indexed", detail: "Incremental indexing pipeline lands in a downstream phase.", status: "Pending"),
    ]

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Source Library")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(AppTheme.primaryText)

                    Text("Manage the folders and files the app is allowed to search. The view shell is separated from bookmark, enumeration, and indexing services.")
                        .foregroundStyle(AppTheme.secondaryText)

                    ForEach(placeholderSources) { source in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(source.name)
                                    .font(.headline)
                                    .foregroundStyle(AppTheme.primaryText)

                                Spacer()

                                Text(source.status)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AppTheme.accent)
                            }

                            Text(source.detail)
                                .foregroundStyle(AppTheme.secondaryText)

                            HStack(spacing: 10) {
                                Button("Reindex") {}
                                    .buttonStyle(.borderedProminent)
                                Button("Re-authorize") {}
                                    .buttonStyle(.bordered)
                                Button("Remove", role: .destructive) {}
                                    .buttonStyle(.bordered)
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
                }
                .padding(20)
            }
        }
        .navigationTitle("Library")
        .navigationBarTitleDisplayMode(.large)
    }
}

private struct LibrarySourceCardModel: Identifiable {
    let id = UUID()
    let name: String
    let detail: String
    let status: String
}

#Preview {
    NavigationStack {
        SourceLibraryView()
    }
    .preferredColorScheme(.dark)
}
