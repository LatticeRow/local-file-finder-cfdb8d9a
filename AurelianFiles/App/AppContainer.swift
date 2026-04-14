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
        self.documentPickerCoordinator = documentPickerCoordinator ?? DocumentPickerCoordinator()
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

    static func live() -> AppContainer {
        AppContainer(modelContainer: makeModelContainer())
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
}
