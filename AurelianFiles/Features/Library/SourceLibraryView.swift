import SwiftUI
import SwiftData

struct SourceLibraryView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \IndexedSource.dateAdded, order: .reverse) private var sources: [IndexedSource]
    @Query private var indexedFiles: [IndexedFile]
    @Query private var extractedContent: [ExtractedContent]

    @State private var activePickerRequest: SourcePickerRequest?
    @State private var importErrorMessage: String?
    @State private var sourcePendingRemoval: IndexedSource?

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Source Library")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(AppTheme.primaryText)

                    Text("Add the folders and files you want to search.")
                        .foregroundStyle(AppTheme.secondaryText)

                    addActionsCard

                    if sources.isEmpty {
                        emptyStateCard
                    } else {
                        ForEach(sources, id: \.id) { source in
                            sourceCard(for: source)
                        }
                    }
                }
                .padding(20)
            }
            .safeAreaPadding(.bottom, AppTheme.tabBarContentInset)
        }
        .navigationTitle("Library")
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $activePickerRequest) { request in
            SecurityScopedDocumentPicker(
                allowedContentTypes: request.mode.allowedContentTypes(
                    fileContentTypes: container.documentPickerCoordinator.supportedFileContentTypes
                ),
                allowsMultipleSelection: request.allowsMultipleSelection
            ) { result in
                handlePickerResult(result, request: request)
            }
        }
        .alert(
            "Couldn’t Update Source",
            isPresented: Binding(
                get: { importErrorMessage != nil },
                set: { if !$0 { importErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importErrorMessage ?? "Try again.")
        }
        .alert(
            "Remove Source?",
            isPresented: Binding(
                get: { sourcePendingRemoval != nil },
                set: { if !$0 { sourcePendingRemoval = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) {
                sourcePendingRemoval = nil
            }
            Button("Remove", role: .destructive) {
                guard let sourcePendingRemoval else {
                    return
                }

                removeSource(sourcePendingRemoval)
                self.sourcePendingRemoval = nil
            }
        } message: {
            Text("This removes the saved source and its local search data.")
        }
    }

    private var addActionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add from Files")
                .font(.headline)
                .foregroundStyle(AppTheme.primaryText)

            HStack(spacing: 12) {
                Button("Add Folder") {
                    activePickerRequest = .add(.folder)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("library.add-folder")

                Button("Add File") {
                    activePickerRequest = .add(.file)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("library.add-file")
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

    private var emptyStateCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No sources yet")
                .font(.headline)
                .foregroundStyle(AppTheme.primaryText)

            Text("Add a folder or file from Files to start searching.")
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

    private func sourceCard(for source: IndexedSource) -> some View {
        let diagnostics = diagnostics(for: source)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(source.displayName)
                        .font(.headline)
                        .foregroundStyle(AppTheme.primaryText)

                    Text(sourceDetail(for: source))
                        .foregroundStyle(AppTheme.secondaryText)
                }

                Spacer(minLength: 12)

                Text(accessBadgeText(for: source))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(source.requiresReauthorization ? AppTheme.primaryText : AppTheme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(accessBadgeBackground(for: source))
                    .clipShape(Capsule())
            }

            if let supportingText = sourceSupportingText(for: source) {
                Text(supportingText)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Files found: \(diagnostics.discoveredCount)")
                Text("Searchable: \(diagnostics.searchableCount)")
                Text("OCR: \(diagnostics.ocrCount)")
            }
            .font(.caption)
            .foregroundStyle(AppTheme.secondaryText)

            if let issueMessage = issueMessage(for: source) {
                Text(issueMessage)
                    .font(.caption)
                    .foregroundStyle(Color.red.opacity(0.88))
            }

            HStack(spacing: 12) {
                if source.requiresReauthorization || !source.isAccessible {
                    Button("Restore Access") {
                        activePickerRequest = .repair(source.id, mode(for: source))
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("library.restore-access.\(source.id.uuidString)")
                } else {
                    Button("Reindex") {
                        container.indexingCoordinator.runReindexSources(withIDs: [source.id])
                    }
                    .buttonStyle(.bordered)
                    .disabled(container.appState.isIndexing)
                    .accessibilityIdentifier("library.reindex.\(source.id.uuidString)")
                }

                Button("Remove", role: .destructive) {
                    sourcePendingRemoval = source
                }
                .buttonStyle(.bordered)
                .disabled(container.appState.isIndexing)
                .accessibilityIdentifier("library.remove.\(source.id.uuidString)")
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

    private func sourceDetail(for source: IndexedSource) -> String {
        switch source.resolvedSourceType {
        case .folder:
            return "Folder"
        case .file:
            return "File"
        }
    }

    private func accessBadgeText(for source: IndexedSource) -> String {
        if source.requiresReauthorization || !source.isAccessible {
            return "Needs Access"
        }

        return "Ready"
    }

    private func accessBadgeBackground(for source: IndexedSource) -> Color {
        if source.requiresReauthorization || !source.isAccessible {
            return Color.red.opacity(0.18)
        }

        return AppTheme.accent.opacity(0.12)
    }

    private func sourceSupportingText(for source: IndexedSource) -> String? {
        if source.requiresReauthorization || !source.isAccessible {
            return "Choose this source again to keep searching it."
        }

        if let lastIndexedAt = source.lastIndexedAt {
            return "Last indexed \(lastIndexedAt.formatted(date: .abbreviated, time: .shortened))"
        }

        return "Ready to index"
    }

    private func issueMessage(for source: IndexedSource) -> String? {
        if source.requiresReauthorization || !source.isAccessible {
            return "Access isn’t available right now."
        }

        if let lastError = source.lastError, !lastError.isEmpty {
            return "This source couldn’t be updated."
        }

        return nil
    }

    private func diagnostics(for source: IndexedSource) -> SourceDiagnostics {
        let filesForSource = indexedFiles.filter { file in
            file.source?.id == source.id || file.sourceID == source.id
        }
        let fileIDs = Set(filesForSource.map(\.id))
        let extractedForSource = extractedContent.filter { content in
            fileIDs.contains(content.file?.id ?? content.fileID)
        }
        let searchableFileIDs = Set(extractedForSource.map { $0.file?.id ?? $0.fileID })
        let ocrCount = filesForSource.filter(\.usedOCR).count

        return SourceDiagnostics(
            discoveredCount: filesForSource.count,
            searchableCount: searchableFileIDs.count,
            ocrCount: ocrCount
        )
    }

    private func handlePickerResult(_ result: Result<[URL], Error>, request: SourcePickerRequest) {
        activePickerRequest = nil

        do {
            let urls = try result.get()
            guard !urls.isEmpty else {
                return
            }

            switch request {
            case .add(let mode):
                let importedSources = try container.documentPickerCoordinator.importSelections(
                    urls,
                    as: mode.sourceType,
                    into: modelContext
                )
                if !importedSources.isEmpty {
                    container.indexingCoordinator.runReindexImportedSources(importedSources)
                }
            case .repair(let sourceID, _):
                guard let source = sources.first(where: { $0.id == sourceID }),
                      let url = urls.first else {
                    throw SourceImportError.invalidSelection
                }

                let importedSource = try container.documentPickerCoordinator.reauthorizeSource(
                    source,
                    with: url,
                    into: modelContext
                )
                container.indexingCoordinator.runReindexImportedSources([importedSource])
            }
        } catch {
            importErrorMessage = error.localizedDescription
        }
    }

    private func mode(for source: IndexedSource) -> SourcePickerMode {
        switch source.resolvedSourceType {
        case .folder:
            return .folder
        case .file:
            return .file
        }
    }

    private func removeSource(_ source: IndexedSource) {
        let indexedFiles = (try? modelContext.fetch(FetchDescriptor<IndexedFile>()))?
            .filter { $0.source?.id == source.id || $0.sourceID == source.id } ?? []
        let indexedFileIDs = Set(indexedFiles.map(\.id))
        let extractedContent = (try? modelContext.fetch(FetchDescriptor<ExtractedContent>()))?
            .filter { indexedFileIDs.contains($0.file?.id ?? $0.fileID) } ?? []

        for file in indexedFiles {
            deleteThumbnailIfPresent(for: file)
            modelContext.delete(file)
        }

        for chunk in extractedContent {
            modelContext.delete(chunk)
        }

        modelContext.delete(source)
        do {
            try modelContext.save()
            container.appState.indexingSummary = container.indexingCoordinator.statusSummary()
        } catch {
            importErrorMessage = "Try again."
        }
    }

    private func deleteThumbnailIfPresent(for file: IndexedFile) {
        guard let thumbnailPath = file.thumbnailPath else {
            return
        }

        try? FileManager.default.removeItem(atPath: thumbnailPath)
    }
}

private struct SourceDiagnostics {
    let discoveredCount: Int
    let searchableCount: Int
    let ocrCount: Int
}

private enum SourcePickerRequest: Identifiable {
    case add(SourcePickerMode)
    case repair(UUID, SourcePickerMode)

    var id: String {
        switch self {
        case .add(let mode):
            return "add-\(mode.rawValue)"
        case .repair(let sourceID, let mode):
            return "repair-\(sourceID.uuidString)-\(mode.rawValue)"
        }
    }

    var mode: SourcePickerMode {
        switch self {
        case .add(let mode), .repair(_, let mode):
            return mode
        }
    }

    var allowsMultipleSelection: Bool {
        switch self {
        case .add:
            return true
        case .repair:
            return false
        }
    }
}

#Preview {
    NavigationStack {
        SourceLibraryView()
    }
    .modelContainer(AppContainer.makeModelContainer(inMemoryOnly: true))
    .environment(AppContainer.preview())
    .preferredColorScheme(.dark)
}
