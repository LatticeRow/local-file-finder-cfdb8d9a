import Foundation

final class DocumentOpenCoordinator {
    private let logger: AppLogger

    init(logger: AppLogger) {
        self.logger = logger
    }

    func previewHint() -> String {
        logger.info("Reporting preview placeholder")
        return "Document preview will be routed through Quick Look in a downstream phase."
    }
}
