import CryptoKit
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
    private let fileMetadataHasher: FileMetadataHasher
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
        self.fileMetadataHasher = FileMetadataHasher(logger: logger)
    }

    func statusSummary() -> String {
        let context = modelContainer.mainContext
        let sourceCount = (try? context.fetchCount(FetchDescriptor<IndexedSource>())) ?? 0
        let indexedFiles = (try? context.fetch(FetchDescriptor<IndexedFile>())) ?? []
        let visibleFileCount = indexedFiles.filter { !$0.isMissing }.count

        switch (sourceCount, visibleFileCount) {
        case (0, _):
            return "No sources yet."
        case (_, 0):
            return "No indexed files yet."
        case (1, 1):
            return "1 source with 1 file ready."
        case (1, _):
            return "1 source with \(visibleFileCount) files ready."
        default:
            return "\(sourceCount) sources with \(visibleFileCount) files ready."
        }
    }

    func reindexAllSources() async throws {
        let context = modelContainer.mainContext
        let sources = try context.fetch(FetchDescriptor<IndexedSource>())
        try await reindex(
            sources: sources,
            context: context,
            preferredURLsBySourceID: [:],
            scopeDescription: "Library scan"
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
            scopeDescription: "Source scan"
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
            scopeDescription: "Imported scan"
        )
    }

    func runReindexAllSources() {
        guard indexingTask == nil else {
            appState.indexingSummary = "Scan already running."
            return
        }

        indexingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.indexingTask = nil }

            do {
                try await self.reindexAllSources()
            } catch {
                self.appState.isIndexing = false
                self.appState.indexingSummary = "Scan failed."
                self.appState.indexingDetail = error.localizedDescription
            }
        }
    }

    func runReindexImportedSources(_ importedSources: [ImportedSource]) {
        guard indexingTask == nil else {
            appState.indexingSummary = "Scan already running."
            return
        }

        indexingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.indexingTask = nil }

            do {
                try await self.reindexImportedSources(importedSources)
            } catch {
                self.appState.isIndexing = false
                self.appState.indexingSummary = "Scan failed."
                self.appState.indexingDetail = error.localizedDescription
            }
        }
    }

    func runReindexSources(withIDs ids: [UUID]) {
        guard indexingTask == nil else {
            appState.indexingSummary = "Scan already running."
            return
        }

        indexingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.indexingTask = nil }

            do {
                try await self.reindexSources(withIDs: ids)
            } catch {
                self.appState.isIndexing = false
                self.appState.indexingSummary = "Scan failed."
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
        try persistProgress(context: context, job: job)

        appState.isIndexing = true
        appState.indexingSummary = sources.isEmpty ? "No sources to scan." : "Preparing scan..."
        appState.indexingDetail = nil

        guard !sources.isEmpty else {
            job.status = IndexingJob.Status.completed.rawValue
            job.finishedAt = .now
            try persistProgress(context: context, job: job)
            appState.isIndexing = false
            appState.indexingSummary = "No sources to scan."
            return
        }

        for source in sources {
            job.currentSourceName = source.displayName
            appState.indexingSummary = "Scanning \(source.displayName)"
            appState.indexingDetail = nil
            try persistProgress(context: context, job: job)

            do {
                try await scanSource(
                    source,
                    withPreferredURL: preferredURLsBySourceID[source.id],
                    context: context,
                    job: job
                )
                job.completedSourceCount += 1
            } catch {
                source.isAccessible = false
                source.requiresReauthorization = true
                source.record(error: error)
                job.record(error: error)
                job.failureCount += 1
                logger.info("Indexing failed for \(source.displayName)")
                try persistProgress(context: context, job: job)
            }

            await Task.yield()
        }

        job.status = job.failureCount > 0
            ? IndexingJob.Status.completedWithFailures.rawValue
            : IndexingJob.Status.completed.rawValue
        job.finishedAt = .now
        job.currentSourceName = nil
        job.currentFileName = nil
        try persistProgress(context: context, job: job)
        appState.isIndexing = false
        appState.indexingDetail = nil
        appState.indexingSummary = completionSummary(for: job)
    }

    private func scanSource(
        _ source: IndexedSource,
        withPreferredURL preferredURL: URL?,
        context: ModelContext,
        job: IndexingJob
    ) async throws {
        let accessURL: URL
        let session: SecurityScopedAccessSession

        if let preferredURL {
            accessURL = preferredURL
            session = try bookmarkManager.startAccessing(accessURL)
        } else {
            let resolvedBookmark = try bookmarkManager.resolveBookmark(source.bookmarkData)
            if let refreshedBookmarkData = try bookmarkManager.refreshBookmarkDataIfNeeded(for: resolvedBookmark) {
                source.bookmarkData = refreshedBookmarkData
                source.lastBookmarkRefreshAt = .now
            }
            accessURL = resolvedBookmark.url
            session = try bookmarkManager.startAccessing(accessURL)
        }

        defer {
            session.stopAccessing()
        }

        let enumerationResult = fileEnumerationService.enumerateVisibleFiles(
            at: accessURL,
            sourceID: source.id,
            sourceName: source.displayName,
            sourceType: source.sourceType
        )
        let enumeratedFiles = enumerationResult.files
        let existingFiles = indexedFiles(for: source, context: context)
        let existingContentIDs = extractedContentFileIDs(for: existingFiles, context: context)

        job.totalCount += enumeratedFiles.count
        let existingByRelativePath = Dictionary(uniqueKeysWithValues: existingFiles.map { ($0.relativePath, $0) })
        var seenPaths = Set<String>()

        for file in enumeratedFiles {
            seenPaths.insert(file.relativePath)
            job.currentFileName = file.fileName
            appState.indexingDetail = file.fileName

            do {
                try processEnumeratedFile(
                    file,
                    source: source,
                    existingFile: existingByRelativePath[file.relativePath],
                    hasStoredContent: existingByRelativePath[file.relativePath].map { existingContentIDs.contains($0.id) } ?? false,
                    context: context,
                    job: job
                )
            } catch {
                let indexedFile = upsertIndexedFile(
                    for: file,
                    source: source,
                    existingFile: existingByRelativePath[file.relativePath],
                    context: context
                )
                clearExtractedContent(for: indexedFile, context: context)
                indexedFile.extractionAttemptedAt = .now
                indexedFile.extractionCompletedAt = nil
                indexedFile.usedOCR = false
                indexedFile.isMissing = false
                indexedFile.extractionState = IndexedFile.ExtractionState.failed.rawValue
                indexedFile.record(error: error)
                job.processedCount += 1
                job.failureCount += 1
                try persistProgress(context: context, job: job)
            }

            await Task.yield()
        }

        markMissingFiles(
            in: existingFiles,
            seenPaths: seenPaths
        )

        source.lastAuthorizedAt = .now
        source.lastIndexedAt = .now
        source.isAccessible = true
        source.requiresReauthorization = false
        source.clearError()
        job.currentFileName = nil
        try persistProgress(context: context, job: job)
    }

    private func processEnumeratedFile(
        _ file: EnumeratedFile,
        source: IndexedSource,
        existingFile: IndexedFile?,
        hasStoredContent: Bool,
        context: ModelContext,
        job: IndexingJob
    ) throws {
        let change = try evaluateChange(
            for: file,
            existingFile: existingFile,
            hasStoredContent: hasStoredContent
        )
        let indexedFile = upsertIndexedFile(
            for: file,
            source: source,
            existingFile: existingFile,
            context: context
        )

        if !change.requiresExtraction {
            indexedFile.isMissing = false
            indexedFile.lastSeenAt = .now
            if let contentHash = change.contentHash {
                indexedFile.contentHash = contentHash
                indexedFile.contentHashAlgorithm = FileMetadataHasher.algorithmName
            }
            if indexedFile.resolvedExtractionState == .missing {
                indexedFile.extractionState = hasStoredContent
                    ? IndexedFile.ExtractionState.indexed.rawValue
                    : IndexedFile.ExtractionState.pending.rawValue
            }
            indexedFile.clearError()
            job.processedCount += 1
            job.skippedCount += 1
            appState.indexingSummary = progressSummary(for: job)
            try persistProgress(context: context, job: job)
            return
        }

        indexedFile.isMissing = false
        indexedFile.lastSeenAt = .now
        indexedFile.extractionAttemptedAt = .now
        indexedFile.extractionCompletedAt = nil
        indexedFile.extractionState = IndexedFile.ExtractionState.indexing.rawValue
        indexedFile.usedOCR = false
        indexedFile.clearError()
        if let contentHash = change.contentHash {
            indexedFile.contentHash = contentHash
            indexedFile.contentHashAlgorithm = FileMetadataHasher.algorithmName
        } else {
            indexedFile.contentHash = nil
            indexedFile.contentHashAlgorithm = nil
        }

        clearExtractedContent(for: indexedFile, context: context)

        let extractedPayloads = contentExtractionService.extractSearchableContent(from: file)
        indexedFile.usedOCR = extractedPayloads.contains(where: \.usedOCR)
        indexedFile.extractionCompletedAt = .now
        indexedFile.lastIndexedAt = .now
        indexedFile.extractionState = extractedPayloads.isEmpty
            ? IndexedFile.ExtractionState.skipped.rawValue
            : IndexedFile.ExtractionState.indexed.rawValue

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
        appState.indexingSummary = progressSummary(for: job)
        try persistProgress(context: context, job: job)
    }

    private func evaluateChange(
        for file: EnumeratedFile,
        existingFile: IndexedFile?,
        hasStoredContent: Bool
    ) throws -> FileChangeDecision {
        guard let existingFile else {
            return FileChangeDecision(requiresExtraction: true, contentHash: try precomputedHashIfNeeded(for: file))
        }

        let needsRetry = existingFile.isMissing
            || existingFile.resolvedExtractionState == .pending
            || existingFile.resolvedExtractionState == .indexing
            || existingFile.resolvedExtractionState == .failed
            || !hasStoredContent

        let sizeMatches = existingFile.byteSize == file.byteSize
        let modificationDatesMatch = timestampsMatch(existingFile.modificationDate, file.modificationDate)

        if sizeMatches, modificationDatesMatch, !needsRetry {
            return FileChangeDecision(requiresExtraction: false, contentHash: nil)
        }

        if sizeMatches, metadataNeedsHashComparison(existingFile.modificationDate, file.modificationDate) {
            let contentHash = try fileMetadataHasher.hashFile(at: file.fileURL)
            if let existingHash = existingFile.contentHash, existingHash == contentHash, !needsRetry {
                return FileChangeDecision(requiresExtraction: false, contentHash: contentHash)
            }

            return FileChangeDecision(requiresExtraction: true, contentHash: contentHash)
        }

        return FileChangeDecision(requiresExtraction: true, contentHash: nil)
    }

    private func upsertIndexedFile(
        for file: EnumeratedFile,
        source: IndexedSource,
        existingFile: IndexedFile?,
        context: ModelContext
    ) -> IndexedFile {
        let indexedFile = existingFile ?? IndexedFile(
            sourceID: source.id,
            fileName: file.fileName,
            relativePath: file.relativePath,
            displayPath: file.displayPath,
            uti: file.uti,
            firstIndexedAt: .now,
            source: source
        )

        indexedFile.source = source
        indexedFile.sourceID = source.id
        indexedFile.fileName = file.fileName
        indexedFile.relativePath = file.relativePath
        indexedFile.displayPath = file.displayPath
        indexedFile.uti = file.uti
        indexedFile.byteSize = file.byteSize
        indexedFile.modificationDate = file.modificationDate
        indexedFile.lastSeenAt = .now

        if existingFile == nil {
            context.insert(indexedFile)
        }

        return indexedFile
    }

    private func indexedFiles(for source: IndexedSource, context: ModelContext) -> [IndexedFile] {
        ((try? context.fetch(FetchDescriptor<IndexedFile>())) ?? []).filter {
            $0.source?.id == source.id || $0.sourceID == source.id
        }
    }

    private func extractedContentFileIDs(for indexedFiles: [IndexedFile], context: ModelContext) -> Set<UUID> {
        let fileIDs = Set(indexedFiles.map(\.id))
        let extractedContent = ((try? context.fetch(FetchDescriptor<ExtractedContent>())) ?? []).filter {
            fileIDs.contains($0.file?.id ?? $0.fileID)
        }

        return Set(extractedContent.map { $0.file?.id ?? $0.fileID })
    }

    private func markMissingFiles(
        in indexedFiles: [IndexedFile],
        seenPaths: Set<String>
    ) {
        for indexedFile in indexedFiles where !seenPaths.contains(indexedFile.relativePath) {
            indexedFile.isMissing = true
            indexedFile.extractionState = IndexedFile.ExtractionState.missing.rawValue
            indexedFile.lastSeenAt = nil
            indexedFile.clearError()
        }
    }

    private func clearExtractedContent(for indexedFile: IndexedFile, context: ModelContext) {
        let contents = ((try? context.fetch(FetchDescriptor<ExtractedContent>())) ?? []).filter {
            ($0.file?.id ?? $0.fileID) == indexedFile.id
        }

        for content in contents {
            context.delete(content)
        }
    }

    private func precomputedHashIfNeeded(for file: EnumeratedFile) throws -> String? {
        guard file.modificationDate == nil else {
            return nil
        }

        return try fileMetadataHasher.hashFile(at: file.fileURL)
    }

    private func metadataNeedsHashComparison(_ oldDate: Date?, _ newDate: Date?) -> Bool {
        oldDate == nil || newDate == nil
    }

    private func timestampsMatch(_ lhs: Date?, _ rhs: Date?) -> Bool {
        guard let lhs, let rhs else {
            return false
        }

        return abs(lhs.timeIntervalSince(rhs)) < 1
    }

    private func persistProgress(context: ModelContext, job: IndexingJob) throws {
        try context.save()
        appState.indexingSummary = progressSummary(for: job)
    }

    private func progressSummary(for job: IndexingJob) -> String {
        if job.resolvedStatus == .running {
            if job.totalCount == 0 {
                return "Scanning files..."
            }

            return "Scanning \(job.processedCount) of \(job.totalCount)"
        }

        return completionSummary(for: job)
    }

    private func completionSummary(for job: IndexingJob) -> String {
        if job.failureCount > 0 {
            return "Scan finished with \(job.failureCount) issues."
        }

        if job.successCount == 0, job.skippedCount == 0 {
            return "Scan finished. No files found."
        }

        if job.successCount == 0 {
            return "Scan finished. Everything is up to date."
        }

        if job.successCount == 1 {
            return "Scan finished. 1 file updated."
        }

        return "Scan finished. \(job.successCount) files updated."
    }
}

private struct FileChangeDecision {
    let requiresExtraction: Bool
    let contentHash: String?
}

private final class FileMetadataHasher {
    static let algorithmName = "sha256"

    private let logger: AppLogger

    init(logger: AppLogger) {
        self.logger = logger
    }

    func hashFile(at url: URL) throws -> String {
        try coordinatedRead(at: url) { coordinatedURL in
            guard let inputStream = InputStream(url: coordinatedURL) else {
                throw CocoaError(.fileReadUnknown)
            }

            inputStream.open()
            defer {
                inputStream.close()
            }

            var hasher = SHA256()
            let bufferSize = 64 * 1024
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer {
                buffer.deallocate()
            }

            while inputStream.hasBytesAvailable {
                let bytesRead = inputStream.read(buffer, maxLength: bufferSize)
                if bytesRead < 0 {
                    throw inputStream.streamError ?? CocoaError(.fileReadUnknown)
                }

                if bytesRead == 0 {
                    break
                }

                hasher.update(bufferPointer: UnsafeRawBufferPointer(start: buffer, count: bytesRead))
            }

            let digest = hasher.finalize()
            return digest.map { String(format: "%02x", $0) }.joined()
        }
    }

    private func coordinatedRead<T>(at url: URL, body: (URL) throws -> T) throws -> T {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var result: T?
        var bodyError: Error?

        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            do {
                result = try body(coordinatedURL)
            } catch {
                bodyError = error
            }
        }

        if let coordinationError {
            logger.info("Hash coordination failed for \(url.lastPathComponent)")
            throw coordinationError
        }

        if let bodyError {
            throw bodyError
        }

        guard let result else {
            throw CocoaError(.fileReadUnknown)
        }

        return result
    }
}
