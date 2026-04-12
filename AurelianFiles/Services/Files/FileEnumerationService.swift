import Foundation

struct EnumeratedFile: Identifiable, Hashable {
    let id = UUID()
    let fileName: String
    let displayPath: String
}

final class FileEnumerationService {
    private let logger: AppLogger

    init(logger: AppLogger) {
        self.logger = logger
    }

    func enumerateVisibleFiles(in sourceName: String) -> [EnumeratedFile] {
        logger.info("Enumerating placeholder files for \(sourceName)")
        return []
    }
}
