import Foundation
import SwiftData

@Model
final class IndexedFile {
    enum ExtractionState: String, CaseIterable, Codable {
        case pending
        case indexing
        case indexed
        case failed
        case skipped
        case missing
    }

    @Attribute(.unique) var id: UUID
    var sourceID: UUID
    var fileName: String
    var relativePath: String
    var displayPath: String
    var uti: String
    var byteSize: Int64
    var modificationDate: Date?
    var contentHash: String?
    var contentHashAlgorithm: String?
    var firstIndexedAt: Date
    var lastIndexedAt: Date?
    var lastSeenAt: Date?
    var isMissing: Bool
    var extractionState: String
    var extractionAttemptedAt: Date?
    var extractionCompletedAt: Date?
    var usedOCR: Bool
    var thumbnailPath: String?
    var lastErrorMessage: String?
    var lastErrorDomain: String?
    var lastErrorCode: Int?
    var lastErrorAt: Date?
    var source: IndexedSource?
    @Relationship(deleteRule: .cascade, inverse: \ExtractedContent.file) var extractedContents: [ExtractedContent]

    init(
        id: UUID = UUID(),
        sourceID: UUID,
        fileName: String,
        relativePath: String,
        displayPath: String,
        uti: String,
        byteSize: Int64 = 0,
        modificationDate: Date? = nil,
        contentHash: String? = nil,
        contentHashAlgorithm: String? = nil,
        firstIndexedAt: Date = .now,
        lastIndexedAt: Date? = nil,
        lastSeenAt: Date? = nil,
        isMissing: Bool = false,
        extractionState: String = "pending",
        extractionAttemptedAt: Date? = nil,
        extractionCompletedAt: Date? = nil,
        usedOCR: Bool = false,
        thumbnailPath: String? = nil,
        lastErrorMessage: String? = nil,
        lastErrorDomain: String? = nil,
        lastErrorCode: Int? = nil,
        lastErrorAt: Date? = nil,
        source: IndexedSource? = nil,
        extractedContents: [ExtractedContent] = []
    ) {
        self.id = id
        self.sourceID = sourceID
        self.fileName = fileName
        self.relativePath = relativePath
        self.displayPath = displayPath
        self.uti = uti
        self.byteSize = byteSize
        self.modificationDate = modificationDate
        self.contentHash = contentHash
        self.contentHashAlgorithm = contentHashAlgorithm
        self.firstIndexedAt = firstIndexedAt
        self.lastIndexedAt = lastIndexedAt
        self.lastSeenAt = lastSeenAt
        self.isMissing = isMissing
        self.extractionState = extractionState
        self.extractionAttemptedAt = extractionAttemptedAt
        self.extractionCompletedAt = extractionCompletedAt
        self.usedOCR = usedOCR
        self.thumbnailPath = thumbnailPath
        self.lastErrorMessage = lastErrorMessage
        self.lastErrorDomain = lastErrorDomain
        self.lastErrorCode = lastErrorCode
        self.lastErrorAt = lastErrorAt
        self.source = source
        self.extractedContents = extractedContents

        if let source {
            self.sourceID = source.id
        }
    }
}

extension IndexedFile {
    var resolvedExtractionState: ExtractionState {
        ExtractionState(rawValue: extractionState) ?? .pending
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

    func record(error: Error, at date: Date = .now) {
        let nsError = error as NSError
        extractionState = ExtractionState.failed.rawValue
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
