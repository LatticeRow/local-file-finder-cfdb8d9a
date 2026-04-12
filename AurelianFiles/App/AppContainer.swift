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
        self.bookmarkManager = bookmarkManager ?? SecurityScopedBookmarkManager(logger: logger)
        self.documentPickerCoordinator = documentPickerCoordinator ?? DocumentPickerCoordinator()
        self.fileEnumerationService = fileEnumerationService ?? FileEnumerationService(logger: logger)
        self.contentExtractionService = contentExtractionService ?? ContentExtractionService(logger: logger)
        self.searchRepository = searchRepository ?? SearchRepository(logger: logger)
        self.documentOpenCoordinator = documentOpenCoordinator ?? DocumentOpenCoordinator(logger: logger)
        self.indexingCoordinator = indexingCoordinator ?? IndexingCoordinator(
            fileEnumerationService: self.fileEnumerationService,
            contentExtractionService: self.contentExtractionService,
            logger: logger
        )
        self.appState = appState ?? AppState()
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
        let configuration = ModelConfiguration(
            schema: Schema([
                IndexedSource.self,
                IndexedFile.self,
                ExtractedContent.self,
                IndexingJob.self,
            ]),
            isStoredInMemoryOnly: inMemoryOnly
        )

        do {
            return try ModelContainer(
                for: IndexedSource.self,
                IndexedFile.self,
                ExtractedContent.self,
                IndexingJob.self,
                configurations: configuration
            )
        } catch {
            fatalError("Failed to create SwiftData container: \(error.localizedDescription)")
        }
    }
}
