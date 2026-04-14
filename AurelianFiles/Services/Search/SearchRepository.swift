import Foundation
import SwiftData

@MainActor
final class SearchRepository {
    private let logger: AppLogger
    private let modelContainer: ModelContainer

    init(logger: AppLogger, modelContainer: ModelContainer) {
        self.logger = logger
        self.modelContainer = modelContainer
    }

    func search(matching query: String) -> [SearchResultItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return []
        }

        logger.info("Running local search for \(trimmedQuery)")

        let context = modelContainer.mainContext
        let files = (try? context.fetch(FetchDescriptor<IndexedFile>())) ?? []
        let extractedContent = (try? context.fetch(FetchDescriptor<ExtractedContent>())) ?? []
        let queryLower = trimmedQuery.lowercased()
        let groupedContent = Dictionary(grouping: extractedContent) { content in
            content.file?.id ?? content.fileID
        }

        let results = files.compactMap { file -> SearchResultItem? in
            guard !file.isMissing else {
                return nil
            }

            let searchableText = groupedContent[file.id]?.map { $0.fullTextNormalized }.joined(separator: " ") ?? ""
            let searchableFields = [file.fileName, file.relativePath, file.displayPath, searchableText]
                .joined(separator: "\n")
                .lowercased()

            guard searchableFields.contains(queryLower) else {
                return nil
            }

            let snippet = groupedContent[file.id]?.first(where: {
                $0.fullTextNormalized.localizedCaseInsensitiveContains(trimmedQuery)
            })?.fullTextPreview
                ?? groupedContent[file.id]?.first?.fullTextPreview
                ?? file.displayPath

            return SearchResultItem(
                title: file.fileName,
                location: file.displayPath,
                snippet: snippet,
                fileType: fileTypeLabel(for: file),
                usedOCR: file.usedOCR
            )
        }

        return results.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private func fileTypeLabel(for file: IndexedFile) -> String {
        if let preferredExtension = URL(filePath: file.fileName).pathExtension.nilIfEmpty {
            return preferredExtension.uppercased()
        }

        return file.uti.components(separatedBy: ".").last?.uppercased() ?? "FILE"
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
