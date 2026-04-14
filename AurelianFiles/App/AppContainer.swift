import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class AppContainer {
    let modelContainer: ModelContainer
    let logger: AppLogger
    let bookmarkManager: SecurityScopedBookmarkManager
    let documentPickerCoordinator: DocumentPickerCoordinator
    let fileEnumerationService: FileEnumerationService
    let contentExtractionService: ContentExtractionService
    let indexingCoordinator: IndexingCoordinator
    let searchRepository: SearchRepository
    let documentOpenCoordinator: DocumentOpenCoordinator
    let appState: AppState
    private var restoreTask: Task<Void, Never>?

    init(
        modelContainer: ModelContainer,
        logger: AppLogger = AppLogger(subsystem: "com.latticerow.aurelianfiles", category: "app"),
        bookmarkManager: SecurityScopedBookmarkManager? = nil,
        documentPickerCoordinator: DocumentPickerCoordinator? = nil,
        fileEnumerationService: FileEnumerationService? = nil,
        contentExtractionService: ContentExtractionService? = nil,
        indexingCoordinator: IndexingCoordinator? = nil,
        searchRepository: SearchRepository? = nil,
        documentOpenCoordinator: DocumentOpenCoordinator? = nil,
        appState: AppState? = nil
    ) {
        self.modelContainer = modelContainer
        self.logger = logger
        let resolvedAppState = appState ?? AppState()
        self.appState = resolvedAppState
        self.bookmarkManager = bookmarkManager ?? SecurityScopedBookmarkManager(logger: logger)
        self.documentPickerCoordinator = documentPickerCoordinator ?? DocumentPickerCoordinator(
            bookmarkManager: self.bookmarkManager,
            logger: logger
        )
        self.fileEnumerationService = fileEnumerationService ?? FileEnumerationService(logger: logger)
        self.contentExtractionService = contentExtractionService ?? ContentExtractionService(logger: logger)
        self.searchRepository = searchRepository ?? SearchRepository(logger: logger, modelContainer: modelContainer)
        self.documentOpenCoordinator = documentOpenCoordinator ?? DocumentOpenCoordinator(logger: logger)
        self.indexingCoordinator = indexingCoordinator ?? IndexingCoordinator(
            fileEnumerationService: self.fileEnumerationService,
            contentExtractionService: self.contentExtractionService,
            bookmarkManager: self.bookmarkManager,
            modelContainer: modelContainer,
            appState: resolvedAppState,
            logger: logger
        )
    }

    static func live(arguments: [String] = ProcessInfo.processInfo.arguments) -> AppContainer {
        let inMemoryOnly = arguments.contains("-ui-testing-in-memory-store")
        let container = AppContainer(modelContainer: makeModelContainer(inMemoryOnly: inMemoryOnly))
        container.prepareForLaunch(arguments: arguments)
        return container
    }

    static func preview() -> AppContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let modelContainer = try? ModelContainer(
            for: IndexedSource.self,
            IndexedFile.self,
            ExtractedContent.self,
            IndexingJob.self,
            configurations: configuration
        )
        return AppContainer(modelContainer: modelContainer ?? makeModelContainer(inMemoryOnly: true))
    }

    static func makeModelContainer(inMemoryOnly: Bool = false) -> ModelContainer {
        let schema = Schema([
            IndexedSource.self,
            IndexedFile.self,
            ExtractedContent.self,
            IndexingJob.self,
        ])

        if inMemoryOnly {
            let configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )

            do {
                return try ModelContainer(
                    for: schema,
                    configurations: configuration
                )
            } catch {
                fatalError("Failed to create SwiftData container: \(error.localizedDescription)")
            }
        }

        let configuration = ModelConfiguration(
            "PrivateLibrary",
            schema: schema,
            url: secureStoreURL(),
            allowsSave: true,
            cloudKitDatabase: .none
        )

        do {
            let container = try ModelContainer(
                for: schema,
                configurations: configuration
            )
            try hardenPersistentStore(at: configuration.url)
            return container
        } catch {
            fatalError("Failed to create SwiftData container: \(error.localizedDescription)")
        }
    }

    private static func secureStoreURL() -> URL {
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        var secureStoreDirectory = (appSupportURL ?? fileManager.temporaryDirectory)
            .appendingPathComponent("PrivateLibrary", isDirectory: true)

        try? fileManager.createDirectory(
            at: secureStoreDirectory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )

        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? secureStoreDirectory.setResourceValues(resourceValues)

        return secureStoreDirectory.appendingPathComponent("PrivateLibrary.store", isDirectory: false)
    }

    private static func hardenPersistentStore(at storeURL: URL) throws {
        let fileManager = FileManager.default
        var storeDirectory = storeURL.deletingLastPathComponent()
        let protectedPaths = [storeDirectory.path, storeURL.path]

        for path in protectedPaths where fileManager.fileExists(atPath: path) {
            try fileManager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: path)
        }

        let sidecarPaths = ["-wal", "-shm"].map { storeURL.path + $0 }
        for path in sidecarPaths where fileManager.fileExists(atPath: path) {
            try fileManager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: path)
        }

        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try storeDirectory.setResourceValues(resourceValues)
    }

    func restorePersistedSourceAccessIfNeeded() {
        restorePersistedSourceAccess(force: false)
    }

    func restorePersistedSourceAccess(force: Bool) {
        guard force || !appState.hasRestoredSourceAccess else {
            return
        }

        guard restoreTask == nil else {
            return
        }

        restoreTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { restoreTask = nil }
            await restoreSourceAccessState()
        }
    }

    private func restoreSourceAccessState() async {
        let context = modelContainer.mainContext
        let sources = (try? context.fetch(FetchDescriptor<IndexedSource>())) ?? []
        var restoredCount = 0
        var failedCount = 0

        guard !sources.isEmpty else {
            appState.hasRestoredSourceAccess = true
            return
        }

        for source in sources {
            do {
                let resolvedBookmark = try bookmarkManager.resolveBookmark(source.bookmarkData)
                if let refreshedBookmarkData = try bookmarkManager.refreshBookmarkDataIfNeeded(for: resolvedBookmark) {
                    source.bookmarkData = refreshedBookmarkData
                    source.lastBookmarkRefreshAt = .now
                }

                let session = try bookmarkManager.startAccessing(resolvedBookmark.url)
                session.stopAccessing()

                source.displayName = resolvedBookmark.url.lastPathComponent
                source.lastAuthorizedAt = .now
                source.isAccessible = true
                source.requiresReauthorization = false
                source.clearError()
                restoredCount += 1
            } catch {
                source.isAccessible = false
                source.requiresReauthorization = true
                source.record(error: error)
                failedCount += 1
            }
        }

        do {
            try context.save()
        } catch {
            logger.info("Failed saving restored source access state")
        }

        appState.hasRestoredSourceAccess = true

        if failedCount > 0 {
            appState.indexingSummary = "\(restoredCount) ready. \(failedCount) need access."
            return
        }

        appState.indexingSummary = indexingCoordinator.statusSummary()
    }

    private func prepareForLaunch(arguments: [String]) {
        guard arguments.contains("-ui-testing-in-memory-store") else {
            return
        }

        seedUITestingData(arguments: arguments)
        appState.hasRestoredSourceAccess = true

        if let selectedTab = selectedTab(from: arguments) {
            appState.selectedTab = selectedTab
        }

        appState.indexingSummary = indexingCoordinator.statusSummary()
    }

    private func seedUITestingData(arguments: [String]) {
        let context = modelContainer.mainContext

        if arguments.contains("-ui-testing-seed-ready-source") {
            let source = IndexedSource(
                displayName: "Board Notes",
                bookmarkData: Data("ready-source".utf8),
                sourceType: IndexedSource.SourceType.folder.rawValue,
                providerIdentifier: "ui-ready-source",
                lastAuthorizedAt: .now,
                lastIndexedAt: .now,
                isAccessible: true
            )
            let file = IndexedFile(
                sourceID: source.id,
                fileName: "Quarterly Brief.txt",
                relativePath: "Quarterly Brief.txt",
                displayPath: "Board Notes/Quarterly Brief.txt",
                uti: "public.plain-text",
                byteSize: 512,
                modificationDate: .now,
                lastIndexedAt: .now,
                lastSeenAt: .now,
                extractionState: IndexedFile.ExtractionState.indexed.rawValue,
                extractionAttemptedAt: .now,
                extractionCompletedAt: .now,
                source: source
            )
            let content = ExtractedContent(
                fileID: file.id,
                fullTextNormalized: "quarterly brief revenue margins and launch timeline",
                fullTextPreview: "Quarterly brief revenue margins and launch timeline",
                snippetSeedText: "Quarterly brief revenue margins and launch timeline",
                tokenCount: 7,
                characterCount: 51,
                file: file
            )

            context.insert(source)
            context.insert(file)
            context.insert(content)
        }

        if arguments.contains("-ui-testing-seed-broken-source") {
            let source = IndexedSource(
                displayName: "Archive Folder",
                bookmarkData: Data("broken-source".utf8),
                sourceType: IndexedSource.SourceType.folder.rawValue,
                providerIdentifier: "ui-broken-source",
                lastAuthorizedAt: Calendar.current.date(byAdding: .day, value: -3, to: .now),
                lastIndexedAt: Calendar.current.date(byAdding: .day, value: -3, to: .now),
                isAccessible: false,
                requiresReauthorization: true,
                lastErrorMessage: "Access isn’t available right now."
            )
            context.insert(source)
        }

        try? context.save()
    }

    private func selectedTab(from arguments: [String]) -> RootTab? {
        guard let tabIndex = arguments.firstIndex(of: "-ui-testing-tab"),
              tabIndex + 1 < arguments.count else {
            return nil
        }

        switch arguments[tabIndex + 1] {
        case "library":
            return .library
        case "settings":
            return .settings
        default:
            return .search
        }
    }
}
