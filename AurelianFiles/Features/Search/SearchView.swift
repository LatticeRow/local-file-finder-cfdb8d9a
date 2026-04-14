import SwiftUI
import SwiftData

struct SearchScene: View {
    @State private var viewModel: SearchViewModel

    init(searchRepository: SearchRepository) {
        _viewModel = State(initialValue: SearchViewModel(searchRepository: searchRepository))
    }

    var body: some View {
        SearchView(viewModel: viewModel)
    }
}

struct SearchView: View {
    @Environment(AppContainer.self) private var container
    @Bindable var viewModel: SearchViewModel
    @Query(sort: \IndexedSource.dateAdded, order: .reverse) private var sources: [IndexedSource]
    @Query(sort: \IndexedFile.fileName, order: .forward) private var indexedFiles: [IndexedFile]

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if sources.isEmpty {
                        introCard
                    }

                    searchField

                    statusCard

                    if sources.isEmpty {
                        OnboardingView()
                    }

                    if viewModel.results.isEmpty {
                        emptyState
                    } else {
                        LazyVStack(spacing: 14) {
                            ForEach(viewModel.results) { item in
                                NavigationLink {
                                    DocumentDetailView(item: item)
                                } label: {
                                    SearchResultCard(item: item)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .safeAreaPadding(.bottom, AppTheme.tabBarContentInset)
        }
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.large)
    }

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Aurelian Files")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(AppTheme.primaryText)

            Text("Add folders or files from Files, then search them here.")
                .foregroundStyle(AppTheme.secondaryText)
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Local index", systemImage: "bolt.horizontal.circle")
                .font(.headline)
                .foregroundStyle(AppTheme.primaryText)

            Text(statusSummary)
                .foregroundStyle(AppTheme.secondaryText)

            if let indexingDetail, container.appState.isIndexing {
                Text(indexingDetail)
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

    private var searchField: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Search your local index", text: $viewModel.query)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(AppTheme.canvas)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .foregroundStyle(AppTheme.primaryText)
                .onSubmit {
                    viewModel.performSearch()
                }
                .onChange(of: viewModel.query) { _, _ in
                    viewModel.performSearch()
                }

            Button("Search") {
                viewModel.performSearch()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(emptyStateTitle)
                .font(.headline)
                .foregroundStyle(AppTheme.primaryText)

            Text(emptyStateMessage)
                .foregroundStyle(AppTheme.secondaryText)
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

    private var statusSummary: String {
        if container.appState.isIndexing {
            return container.appState.indexingSummary
        }

        if let indexingSummary = container.appState.indexingSummary.nilIfPlaceholder {
            return indexingSummary
        }

        switch sources.count {
        case 0:
            return "No folders or files added yet."
        default:
            return indexedSummary
        }
    }

    private var emptyStateTitle: String {
        sources.isEmpty ? "Add a source to get started" : "No matches yet"
    }

    private var emptyStateMessage: String {
        if sources.isEmpty {
            return "Add folders or files from Files to start searching."
        }

        return "Try a filename or a word from a document."
    }

    private var indexedSummary: String {
        switch (sources.count, indexedFiles.count) {
        case (1, 1):
            return "1 source with 1 searchable file."
        case (1, _):
            return "1 source with \(indexedFiles.count) searchable files."
        default:
            return "\(sources.count) sources with \(indexedFiles.count) searchable files."
        }
    }

    private var indexingDetail: String? {
        container.appState.indexingDetail
    }
}

private struct SearchResultCard: View {
    let item: SearchResultItem

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.headline)
                        .foregroundStyle(AppTheme.primaryText)

                    Text(item.location)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                }

                Spacer(minLength: 12)

                Text(item.fileType)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppTheme.accent.opacity(0.12))
                    .clipShape(Capsule())
            }

            Text(item.snippet)
                .foregroundStyle(AppTheme.secondaryText)

            if item.usedOCR {
                Label("OCR", systemImage: "viewfinder")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.primaryText)
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

private extension String {
    var nilIfPlaceholder: String? {
        switch self {
        case "No indexing activity yet.", "Indexing is already running.":
            return nil
        default:
            return self
        }
    }
}

#Preview {
    let container = AppContainer.preview()

    NavigationStack {
        SearchScene(searchRepository: container.searchRepository)
            .environment(container)
    }
    .modelContainer(container.modelContainer)
    .preferredColorScheme(.dark)
}
