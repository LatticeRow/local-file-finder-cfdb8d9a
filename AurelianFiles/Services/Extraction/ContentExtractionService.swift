import Foundation

final class ContentExtractionService {
    private let logger: AppLogger

    init(logger: AppLogger) {
        self.logger = logger
    }

    func extractionPipelineDescription() -> String {
        logger.info("Reporting extraction pipeline")
        return "Plain text, PDF text, image OCR, and scanned PDF OCR placeholders are wired through Services."
    }
}
