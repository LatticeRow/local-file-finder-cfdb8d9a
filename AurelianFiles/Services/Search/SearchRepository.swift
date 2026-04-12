import Foundation

final class SearchRepository {
    private let logger: AppLogger

    init(logger: AppLogger) {
        self.logger = logger
    }

    func placeholderResults(matching query: String) -> [SearchResultItem] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        logger.info("Generating placeholder search results for \(query)")

        return [
            SearchResultItem(
                title: "Welcome to Aurelian Files",
                location: "Search inside the folders and files you add from Files",
                snippet: "This shell is ready for indexing, OCR, and local keyword search.",
                fileType: "TXT",
                usedOCR: false
            ),
        ]
    }
}
