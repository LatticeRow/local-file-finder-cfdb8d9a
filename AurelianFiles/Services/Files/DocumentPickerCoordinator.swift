import CryptoKit
import Foundation
import SwiftData
import UniformTypeIdentifiers

enum SupportedSearchContentTypes {
    static let markdownType = UTType(filenameExtension: "md")
        ?? UTType(filenameExtension: "markdown")
        ?? .plainText

    static let pickerFileContentTypes: [UTType] = {
        var contentTypes: [UTType] = [
            .plainText,
            .pdf,
            .png,
            .jpeg,
            .heic,
        ]

        if !contentTypes.contains(markdownType) {
            contentTypes.insert(markdownType, at: 1)
        }

        return contentTypes
    }()

    static let supportedFileExtensions: Set<String> = [
        "txt",
        "md",
        "markdown",
        "pdf",
        "png",
        "jpg",
        "jpeg",
        "heic",
    ]

    static func supportedIdentifier(for fileURL: URL, declaredType: UTType?) -> String? {
        if let declaredType {
            if declaredType.conforms(to: .pdf) {
                return UTType.pdf.identifier
            }

            if declaredType.conforms(to: .png) {
                return UTType.png.identifier
            }

            if declaredType.conforms(to: .jpeg) {
                return UTType.jpeg.identifier
            }

            if declaredType.conforms(to: .heic) {
                return UTType.heic.identifier
            }

            let fileExtension = normalizedFileExtension(for: fileURL)
            if declaredType.conforms(to: .plainText), fileExtension == "txt" {
                return UTType.plainText.identifier
            }

            if ["md", "markdown"].contains(fileExtension) {
                return markdownType.identifier
            }
        }

        switch normalizedFileExtension(for: fileURL) {
        case "txt":
            return UTType.plainText.identifier
        case "md", "markdown":
            return markdownType.identifier
        case "pdf":
            return UTType.pdf.identifier
        case "png":
            return UTType.png.identifier
        case "jpg", "jpeg":
            return UTType.jpeg.identifier
        case "heic":
            return UTType.heic.identifier
        default:
            return nil
        }
    }

    private static func normalizedFileExtension(for fileURL: URL) -> String {
        fileURL.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

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

    let supportedContentTypes: [UTType] = [.folder] + SupportedSearchContentTypes.pickerFileContentTypes

    init(bookmarkManager: SecurityScopedBookmarkManager, logger: AppLogger) {
        self.bookmarkManager = bookmarkManager
        self.logger = logger
    }

    var supportedFileContentTypes: [UTType] {
        SupportedSearchContentTypes.pickerFileContentTypes
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
