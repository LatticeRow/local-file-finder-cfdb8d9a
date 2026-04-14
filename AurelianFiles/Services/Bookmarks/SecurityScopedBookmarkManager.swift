import Foundation

struct ResolvedBookmark {
    let url: URL
    let isStale: Bool
}

final class SecurityScopedAccessSession {
    let url: URL
    private let didAccess: Bool

    init(url: URL, didAccess: Bool) {
        self.url = url
        self.didAccess = didAccess
    }

    func stopAccessing() {
        guard didAccess else {
            return
        }

        url.stopAccessingSecurityScopedResource()
    }

    deinit {
        stopAccessing()
    }
}

final class SecurityScopedBookmarkManager {
    private let logger: AppLogger

    init(logger: AppLogger) {
        self.logger = logger
    }

    func createBookmark(for url: URL) throws -> Data {
        logger.info("Creating bookmark for \(url.lastPathComponent)")
        return try url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    func resolveBookmark(_ data: Data) throws -> ResolvedBookmark {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: [.withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return ResolvedBookmark(url: url, isStale: isStale)
    }

    func refreshBookmarkDataIfNeeded(for resolvedBookmark: ResolvedBookmark) throws -> Data? {
        guard resolvedBookmark.isStale else {
            return nil
        }

        logger.info("Refreshing stale bookmark for \(resolvedBookmark.url.lastPathComponent)")
        return try createBookmark(for: resolvedBookmark.url)
    }

    func startAccessing(_ url: URL) throws -> SecurityScopedAccessSession {
        let didAccess = url.startAccessingSecurityScopedResource()
        guard didAccess else {
            logger.info("Security-scoped access failed for \(url.lastPathComponent)")
            throw BookmarkAccessError.accessDenied(url.lastPathComponent)
        }

        return SecurityScopedAccessSession(url: url, didAccess: didAccess)
    }

    func validateAccess(to data: Data) throws -> ResolvedBookmark {
        let resolvedBookmark = try resolveBookmark(data)
        let session = try startAccessing(resolvedBookmark.url)
        session.stopAccessing()
        return resolvedBookmark
    }
}

enum BookmarkAccessError: LocalizedError {
    case accessDenied(String)

    var errorDescription: String? {
        switch self {
        case .accessDenied(let name):
            return "Aurelian Files can’t open \(name) right now."
        }
    }
}
