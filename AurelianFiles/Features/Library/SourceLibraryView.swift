import SwiftUI
import SwiftData

struct SourceLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \IndexedSource.dateAdded, order: .reverse) private var sources: [IndexedSource]
    @Query private var indexedFiles: [IndexedFile]
    @Query private var extractedContent: [ExtractedContent]

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Source Library")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(AppTheme.primaryText)

                    Text("Manage the folders and files Aurelian Files can search.")
                        .foregroundStyle(AppTheme.secondaryText)

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
    }

    private var emptyStateCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No authorized sources yet")
                .font(.headline)
                .foregroundStyle(AppTheme.primaryText)

            Text("Use the Search tab to add folders or individual files from Files. Added items are stored locally and appear here.")
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(source.displayName)
                        .font(.headline)
                        .foregroundStyle(AppTheme.primaryText)

                    Text(sourceDetail(for: source))
                        .foregroundStyle(AppTheme.secondaryText)
                }

                Spacer(minLength: 12)

                Text(source.sourceType.capitalized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppTheme.accent.opacity(0.12))
                    .clipShape(Capsule())
            }

            if let lastAuthorizedAt = source.lastAuthorizedAt {
                Text("Authorized \(lastAuthorizedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
            }

            let diagnostics = diagnostics(for: source)

            VStack(alignment: .leading, spacing: 4) {
                Text("Files discovered: \(diagnostics.discoveredCount)")
                Text("Files with searchable text: \(diagnostics.searchableCount)")
                Text("Files using OCR: \(diagnostics.ocrCount)")
            }
            .font(.caption)
            .foregroundStyle(AppTheme.secondaryText)

            if let issueMessage = issueMessage(for: source) {
                Text(issueMessage)
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.9))
            }

            if let diagnosticsNote = diagnostics.note {
                Text(diagnosticsNote)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }

            Button("Remove", role: .destructive) {
                removeSource(source)
            }
            .buttonStyle(.bordered)
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
        switch source.sourceType {
        case "folder":
            return "Folder from Files"
        case "file":
            return "File from Files"
        default:
            return "Added from Files"
        }
    }

    private func issueMessage(for source: IndexedSource) -> String? {
        if source.requiresReauthorization {
            return "Access needs to be restored for this source."
        }

        if let lastError = source.lastError, !lastError.isEmpty {
            return "This source couldn't be indexed."
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

        let note: String?
        if issueMessage(for: source) != nil {
            note = nil
        } else if source.lastIndexedAt == nil {
            note = "Ready to index."
        } else if filesForSource.isEmpty {
            note = "No files were found."
        } else if searchableFileIDs.isEmpty {
            note = "Files were found, but no text is searchable yet."
        } else if ocrCount > 0 {
            note = "\(searchableFileIDs.count) files are searchable. \(ocrCount) use OCR."
        } else {
            note = "\(searchableFileIDs.count) files are searchable."
        }

        return SourceDiagnostics(
            discoveredCount: filesForSource.count,
            searchableCount: searchableFileIDs.count,
            ocrCount: ocrCount,
            note: note
        )
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
        } catch {
            assertionFailure("Failed to remove source: \(error.localizedDescription)")
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
    let note: String?
}

#Preview {
    NavigationStack {
        SourceLibraryView()
    }
    .modelContainer(AppContainer.makeModelContainer(inMemoryOnly: true))
    .preferredColorScheme(.dark)
}
