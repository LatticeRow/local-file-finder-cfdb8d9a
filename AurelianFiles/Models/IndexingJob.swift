import Foundation
import SwiftData

@Model
final class IndexingJob {
    @Attribute(.unique) var id: UUID
    var scopeDescription: String
    var startedAt: Date
    var finishedAt: Date?
    var status: String
    var processedCount: Int
    var successCount: Int
    var failureCount: Int
    var currentFileName: String?

    init(
        id: UUID = UUID(),
        scopeDescription: String,
        startedAt: Date = .now,
        finishedAt: Date? = nil,
        status: String = "idle",
        processedCount: Int = 0,
        successCount: Int = 0,
        failureCount: Int = 0,
        currentFileName: String? = nil
    ) {
        self.id = id
        self.scopeDescription = scopeDescription
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.status = status
        self.processedCount = processedCount
        self.successCount = successCount
        self.failureCount = failureCount
        self.currentFileName = currentFileName
    }
}
