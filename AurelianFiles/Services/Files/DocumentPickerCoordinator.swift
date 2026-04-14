import CryptoKit
import Foundation
import SwiftData
import UniformTypeIdentifiers

struct ImportedSource: Hashable {
    let id: UUID
    let url: URL
}

enum SourceImportError: LocalizedError {
    case duplicateSelection
    case invalidSelection

    var errorDescription: String? {
        switch self {
        case .duplicateSelection:
            return "That source is already in your library."
        case .invalidSelection:
            return "Choose the source again."
        }
    }
}

final class DocumentPickerCoordinator {
    private let bookmarkManager: SecurityScopedBookmarkManager
    private let logger: AppLogger

    let supportedContentTypes: [UTType] = [
        .folder,
        .plainText,
        .pdf,
        .png,
        .jpeg,
        .heic,
    ]

    init(bookmarkManager: SecurityScopedBookmarkManager, logger: AppLogger) {
        self.bookmarkManager = bookmarkManager
        self.logger = logger
    }

    var supportedFileContentTypes: [UTType] {
        supportedContentTypes.filter { $0 != .folder }
    }

    func importSelections(
        _ urls: [URL],
        as sourceType: IndexedSource.SourceType,
        into modelContext: ModelContext
    ) throws -> [ImportedSource] {
        let existingSources = try modelContext.fetch(FetchDescriptor<IndexedSource>())
        return try persistSelections(
            urls,
            as: sourceType,
            existingSources: existingSources,
            replacing: nil,
            into: modelContext
        )
    }

    func reauthorizeSource(
        _ source: IndexedSource,
        with url: URL,
        into modelContext: ModelContext
    ) throws -> ImportedSource {
        let existingSources = try modelContext.fetch(FetchDescriptor<IndexedSource>())
        let importedSources = try persistSelections(
            [url],
            as: source.resolvedSourceType,
            existingSources: existingSources,
            replacing: source,
            into: modelContext
        )

        guard let importedSource = importedSources.first else {
            throw SourceImportError.invalidSelection
        }

        return importedSource
    }

    private func persistSelections(
        _ urls: [URL],
        as sourceType: IndexedSource.SourceType,
        existingSources: [IndexedSource],
        replacing sourceToReplace: IndexedSource?,
        into modelContext: ModelContext
    ) throws -> [ImportedSource] {
        let duplicateIdentifiers = Set(
            existingSources
                .filter { $0.id != sourceToReplace?.id }
                .compactMap(\.providerIdentifier)
        )

        var importedSources: [ImportedSource] = []

        for url in urls {
            let providerIdentifier = sourceIdentifier(for: url, sourceType: sourceType)
            if duplicateIdentifiers.contains(providerIdentifier) {
                if sourceToReplace != nil {
                    throw SourceImportError.duplicateSelection
                }
                continue
            }

            let bookmarkData = try bookmarkManager.createBookmark(for: url)
            _ = try bookmarkManager.validateAccess(to: bookmarkData)

            let source = sourceToReplace ?? IndexedSource(
                displayName: url.lastPathComponent,
                sourceType: sourceType.rawValue
            )

            source.displayName = url.lastPathComponent
            source.bookmarkData = bookmarkData
            source.sourceType = sourceType.rawValue
            source.providerIdentifier = providerIdentifier
            source.lastAuthorizedAt = .now
            source.lastBookmarkRefreshAt = nil
            source.isAccessible = true
            source.requiresReauthorization = false
            source.clearError()

            if sourceToReplace == nil {
                modelContext.insert(source)
            }

            importedSources.append(ImportedSource(id: source.id, url: url))
            logger.info("Persisted source \(url.lastPathComponent)")
        }

        if !importedSources.isEmpty {
            try modelContext.save()
        }

        return importedSources
    }

    private func sourceIdentifier(for url: URL, sourceType: IndexedSource.SourceType) -> String {
        let input = "\(sourceType.rawValue)|\(url.standardizedFileURL.absoluteString)"
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
