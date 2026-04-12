import Foundation

final class IndexingCoordinator {
    private let fileEnumerationService: FileEnumerationService
    private let contentExtractionService: ContentExtractionService
    private let logger: AppLogger

    init(
        fileEnumerationService: FileEnumerationService,
        contentExtractionService: ContentExtractionService,
        logger: AppLogger
    ) {
        self.fileEnumerationService = fileEnumerationService
        self.contentExtractionService = contentExtractionService
        self.logger = logger
    }

    func statusSummary() -> String {
        _ = fileEnumerationService.enumerateVisibleFiles(in: "Files")
        _ = contentExtractionService.extractionPipelineDescription()
        logger.info("Reporting indexing placeholder summary")
        return "Ready for source authorization, enumeration, and extraction services."
    }
}
