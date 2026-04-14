import Foundation
import SwiftData

@MainActor
final class IndexingCoordinator {
    private let fileEnumerationService: FileEnumerationService
    private let contentExtractionService: ContentExtractionService
    private let bookmarkManager: SecurityScopedBookmarkManager
    private let modelContainer: ModelContainer
    private let appState: AppState
    private let logger: AppLogger
    private var indexingTask: Task<Void, Never>?

    init(
        fileEnumerationService: FileEnumerationService,
        contentExtractionService: ContentExtractionService,
        bookmarkManager: SecurityScopedBookmarkManager,
        modelContainer: ModelContainer,
        appState: AppState,
        logger: AppLogger
    ) {
        self.fileEnumerationService = fileEnumerationService
        self.contentExtractionService = contentExtractionService
        self.bookmarkManager = bookmarkManager
        self.modelContainer = modelContainer
        self.appState = appState
        self.logger = logger
    }

    func statusSummary() -> String {
        let context = modelContainer.mainContext
        let sourceCount = (try? context.fetchCount(FetchDescriptor<IndexedSource>())) ?? 0
        let fileCount = (try? context.fetchCount(FetchDescriptor<IndexedFile>())) ?? 0

        switch (sourceCount, fileCount) {
        case (0, _):
            return "No authorized sources yet."
        case (_, 0):
            return "Sources are authorized, but no files have been indexed yet."
        case (1, 1):
            return "1 source indexed recursively with 1 searchable file."
        case (1, _):
            return "1 source indexed recursively with \(fileCount) searchable files."
        default:
            return "\(sourceCount) sources indexed recursively with \(fileCount) searchable files."
        }
    }

    func reindexAllSources() async throws {
        let context = modelContainer.mainContext
        let sources = try context.fetch(FetchDescriptor<IndexedSource>())
        try await reindex(
            sources: sources,
            context: context,
            preferredURLsBySourceID: [:],
            scopeDescription: "Full library reindex"
        )
    }

    func reindexSources(withIDs ids: [UUID]) async throws {
        let idSet = Set(ids)
        let context = modelContainer.mainContext
        let allSources = try context.fetch(FetchDescriptor<IndexedSource>())
        let matchingSources = allSources.filter { idSet.contains($0.id) }
        try await reindex(
            sources: matchingSources,
            context: context,
            preferredURLsBySourceID: [:],
            scopeDescription: "Selected source reindex"
        )
    }

    func reindexImportedSources(_ importedSources: [ImportedSource]) async throws {
        let preferredURLsBySourceID = Dictionary(uniqueKeysWithValues: importedSources.map { ($0.id, $0.url) })
        let sourceIDs = Set(preferredURLsBySourceID.keys)
        let context = modelContainer.mainContext
        let allSources = try context.fetch(FetchDescriptor<IndexedSource>())
        let matchingSources = allSources.filter { sourceIDs.contains($0.id) }
        try await reindex(
            sources: matchingSources,
            context: context,
            preferredURLsBySourceID: preferredURLsBySourceID,
            scopeDescription: "Imported source indexing"
        )
    }

    func runReindexAllSources() {
        guard indexingTask == nil else {
            appState.indexingSummary = "Indexing is already running."
            return
        }

        indexingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.indexingTask = nil }

            do {
                try await self.reindexAllSources()
            } catch {
                self.appState.isIndexing = false
                self.appState.indexingSummary = "Indexing failed."
                self.appState.indexingDetail = error.localizedDescription
            }
        }
    }

    func runReindexImportedSources(_ importedSources: [ImportedSource]) {
        guard indexingTask == nil else {
            appState.indexingSummary = "Indexing is already running."
            return
        }

        indexingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.indexingTask = nil }

            do {
                try await self.reindexImportedSources(importedSources)
            } catch {
                self.appState.isIndexing = false
                self.appState.indexingSummary = "Indexing failed."
                self.appState.indexingDetail = error.localizedDescription
            }
        }
    }

    private func reindex(
        sources: [IndexedSource],
        context: ModelContext,
        preferredURLsBySourceID: [UUID: URL],
        scopeDescription: String
    ) async throws {
        let job = IndexingJob(
            scopeDescription: scopeDescription,
            status: IndexingJob.Status.running.rawValue,
            sourceCount: sources.count
        )
        context.insert(job)
        try context.save()

        appState.isIndexing = true
        appState.indexingSummary = sources.isEmpty ? "No sources available to index." : "Preparing local index..."
        appState.indexingDetail = nil

        for source in sources {
            try removeIndexedData(for: source, context: context)
            job.currentSourceName = source.displayName

            do {
                let accessURL: URL
                let didAccess: Bool

                if let preferredURL = preferredURLsBySourceID[source.id] {
                    accessURL = preferredURL
                    didAccess = accessURL.startAccessingSecurityScopedResource()
                } else {
                    let resolvedBookmark = try bookmarkManager.resolveBookmark(source.bookmarkData)
                    if resolvedBookmark.isStale {
                        source.bookmarkData = try bookmarkManager.createBookmark(for: resolvedBookmark.url)
                        source.lastBookmarkRefreshAt = .now
                    }
                    accessURL = resolvedBookmark.url
                    didAccess = accessURL.startAccessingSecurityScopedResource()
                }

                guard didAccess else {
                    throw IndexingError.unableToAccessSource(source.displayName)
                }

                defer {
                    if didAccess {
                        accessURL.stopAccessingSecurityScopedResource()
                    }
                }

                let files = fileEnumerationService.enumerateVisibleFiles(
                    at: accessURL,
                    sourceID: source.id,
                    sourceName: source.displayName,
                    sourceType: source.sourceType
                )

                job.totalCount += files.count
                if !files.isEmpty {
                    appState.indexingSummary = "Indexing \(source.displayName)"
                }

                for file in files {
                    job.currentFileName = file.fileName
                    appState.indexingDetail = file.fileName

                    let indexedFile = IndexedFile(
                        sourceID: file.sourceID,
                        fileName: file.fileName,
                        relativePath: file.relativePath,
                        displayPath: file.displayPath,
                        uti: file.uti,
                        byteSize: file.byteSize,
                        modificationDate: file.modificationDate,
                        firstIndexedAt: .now,
                        lastIndexedAt: .now,
                        lastSeenAt: .now,
                        extractionState: IndexedFile.ExtractionState.indexing.rawValue,
                        extractionAttemptedAt: .now,
                        source: source
                    )
                    context.insert(indexedFile)

                    let extractedPayloads = contentExtractionService.extractSearchableContent(from: file)
                    let usedOCR = extractedPayloads.contains(where: \.usedOCR)
                    indexedFile.usedOCR = usedOCR
                    indexedFile.extractionCompletedAt = .now
                    indexedFile.extractionState = extractedPayloads.isEmpty
                        ? IndexedFile.ExtractionState.skipped.rawValue
                        : IndexedFile.ExtractionState.indexed.rawValue
                    indexedFile.clearError()

                    for extracted in extractedPayloads {
                        let content = ExtractedContent(
                            fileID: indexedFile.id,
                            chunkIndex: extracted.chunkIndex,
                            pageNumber: extracted.pageNumber,
                            fullTextNormalized: extracted.normalizedText,
                            fullTextPreview: extracted.preview,
                            snippetSeedText: extracted.preview,
                            tokenCount: extracted.tokenCount,
                            characterCount: extracted.normalizedText.count,
                            extractionMethod: extracted.usedOCR ? "ocr" : "native",
                            usedOCR: extracted.usedOCR,
                            file: indexedFile
                        )
                        context.insert(content)
                    }

                    job.processedCount += 1
                    if extractedPayloads.isEmpty {
                        job.skippedCount += 1
                    } else {
                        job.successCount += 1
                    }
                    appState.indexingSummary = "Indexed \(job.processedCount) of \(job.totalCount) files"

                    if job.processedCount.isMultiple(of: 8) {
                        try context.save()
                        await Task.yield()
                    }
                }

                source.lastAuthorizedAt = .now
                source.lastIndexedAt = .now
                source.isAccessible = true
                source.requiresReauthorization = false
                source.clearError()
                job.completedSourceCount += 1
            } catch {
                source.isAccessible = false
                source.requiresReauthorization = true
                source.record(error: error)
                job.record(error: error)
                job.failureCount += 1
                logger.info("Indexing failed for \(source.displayName)")
            }

            await Task.yield()
        }

        job.status = job.failureCount > 0
            ? IndexingJob.Status.completedWithFailures.rawValue
            : IndexingJob.Status.completed.rawValue
        job.finishedAt = .now
        job.currentSourceName = nil
        job.currentFileName = nil
        try context.save()
        appState.isIndexing = false
        appState.indexingDetail = nil
        appState.indexingSummary = completionSummary(for: job)
    }

    private func removeIndexedData(for source: IndexedSource, context: ModelContext) throws {
        let indexedFiles = try context.fetch(FetchDescriptor<IndexedFile>())
            .filter { $0.sourceID == source.id }
        let indexedFileIDs = Set(indexedFiles.map(\.id))
        let extractedContent = try context.fetch(FetchDescriptor<ExtractedContent>())
            .filter { indexedFileIDs.contains($0.fileID) }

        for content in extractedContent {
            context.delete(content)
        }

        for file in indexedFiles {
            context.delete(file)
        }
    }

    private func completionSummary(for job: IndexingJob) -> String {
        if job.failureCount > 0 {
            return "Indexed \(job.successCount) files. \(job.failureCount) sources need attention."
        }

        if job.skippedCount > 0, job.successCount == 0 {
            return "Indexing finished. Files were found, but none produced searchable text."
        }

        switch job.successCount {
        case 0:
            return "Indexing finished with no searchable files."
        case 1:
            return "Indexing finished with 1 searchable file."
        default:
            return "Indexing finished with \(job.successCount) searchable files."
        }
    }
}

private enum IndexingError: LocalizedError {
    case unableToAccessSource(String)

    var errorDescription: String? {
        switch self {
        case .unableToAccessSource(let sourceName):
            return "The app could not access \(sourceName) for indexing."
        }
    }
}
