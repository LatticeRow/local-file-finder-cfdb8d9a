import Foundation
import SwiftData

@Model
final class IndexingJob {
    enum Status: String, CaseIterable, Codable {
        case idle
        case running
        case completed
        case completedWithFailures
        case failed
        case cancelled
    }

    @Attribute(.unique) var id: UUID
    var scopeDescription: String
    var startedAt: Date
    var finishedAt: Date?
    var status: String
    var totalCount: Int
    var processedCount: Int
    var successCount: Int
    var failureCount: Int
    var skippedCount: Int
    var sourceCount: Int
    var completedSourceCount: Int
    var currentSourceName: String?
    var currentFileName: String?
    var lastErrorMessage: String?
    var lastErrorDomain: String?
    var lastErrorCode: Int?
    var lastErrorAt: Date?

    init(
        id: UUID = UUID(),
        scopeDescription: String,
        startedAt: Date = .now,
        finishedAt: Date? = nil,
        status: String = "idle",
        totalCount: Int = 0,
        processedCount: Int = 0,
        successCount: Int = 0,
        failureCount: Int = 0,
        skippedCount: Int = 0,
        sourceCount: Int = 0,
        completedSourceCount: Int = 0,
        currentSourceName: String? = nil,
        currentFileName: String? = nil,
        lastErrorMessage: String? = nil,
        lastErrorDomain: String? = nil,
        lastErrorCode: Int? = nil,
        lastErrorAt: Date? = nil
    ) {
        self.id = id
        self.scopeDescription = scopeDescription
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.status = status
        self.totalCount = totalCount
        self.processedCount = processedCount
        self.successCount = successCount
        self.failureCount = failureCount
        self.skippedCount = skippedCount
        self.sourceCount = sourceCount
        self.completedSourceCount = completedSourceCount
        self.currentSourceName = currentSourceName
        self.currentFileName = currentFileName
        self.lastErrorMessage = lastErrorMessage
        self.lastErrorDomain = lastErrorDomain
        self.lastErrorCode = lastErrorCode
        self.lastErrorAt = lastErrorAt
    }
}

extension IndexingJob {
    var resolvedStatus: Status {
        Status(rawValue: status) ?? .idle
    }

    var lastError: String? {
        get { lastErrorMessage }
        set {
            lastErrorMessage = newValue
            if newValue == nil || newValue?.isEmpty == true {
                lastErrorDomain = nil
                lastErrorCode = nil
                lastErrorAt = nil
            } else if lastErrorAt == nil {
                lastErrorAt = .now
            }
        }
    }

    var progressFraction: Double {
        guard totalCount > 0 else {
            return 0
        }

        return Double(processedCount) / Double(totalCount)
    }

    func record(error: Error, at date: Date = .now) {
        let nsError = error as NSError
        lastErrorMessage = nsError.localizedDescription
        lastErrorDomain = nsError.domain
        lastErrorCode = nsError.code
        lastErrorAt = date
    }

    func clearError() {
        lastErrorMessage = nil
        lastErrorDomain = nil
        lastErrorCode = nil
        lastErrorAt = nil
    }
}
