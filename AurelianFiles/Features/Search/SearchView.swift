import SwiftUI

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
    @Bindable var viewModel: SearchViewModel
    @Environment(AppContainer.self) private var container

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Aurelian Files")
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(AppTheme.primaryText)

                        Text("Private document search with an injectable SwiftData core and native iPhone shell.")
                            .foregroundStyle(AppTheme.secondaryText)
                    }

                    OnboardingView()

                    statusCard

                    searchField

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
        }
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            viewModel.statusSummary = container.indexingCoordinator.statusSummary()
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Indexing shell", systemImage: "bolt.horizontal.circle")
                .font(.headline)
                .foregroundStyle(AppTheme.primaryText)

            Text(viewModel.statusSummary)
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

            Button("Run Placeholder Search") {
                viewModel.performSearch()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Search target ready")
                .font(.headline)
                .foregroundStyle(AppTheme.primaryText)

            Text("Add Files-backed sources in a downstream phase. The shared container, SwiftData store, and tab shell are already in place.")
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

#Preview {
    NavigationStack {
        SearchScene(searchRepository: SearchRepository(logger: AppLogger(subsystem: "preview", category: "search")))
            .environment(AppContainer.preview())
    }
    .preferredColorScheme(.dark)
}
