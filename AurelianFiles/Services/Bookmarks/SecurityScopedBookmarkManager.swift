import Foundation

struct ResolvedBookmark {
    let url: URL
    let isStale: Bool
}

final class SecurityScopedBookmarkManager {
    private let logger: AppLogger

    init(logger: AppLogger) {
        self.logger = logger
    }

    func createBookmark(for url: URL) throws -> Data {
        logger.info("Creating bookmark for \(url.lastPathComponent)")
        return try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    func resolveBookmark(_ data: Data) throws -> ResolvedBookmark {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: .withoutUI,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return ResolvedBookmark(url: url, isStale: isStale)
    }
}
