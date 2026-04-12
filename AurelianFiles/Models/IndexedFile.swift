import Foundation
import SwiftData

@Model
final class IndexedFile {
    @Attribute(.unique) var id: UUID
    var sourceID: UUID
    var fileName: String
    var relativePath: String
    var displayPath: String
    var uti: String
    var byteSize: Int64
    var modificationDate: Date?
    var contentHash: String?
    var lastIndexedAt: Date?
    var isMissing: Bool
    var extractionState: String
    var usedOCR: Bool
    var thumbnailPath: String?
    var lastError: String?

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
        lastIndexedAt: Date? = nil,
        isMissing: Bool = false,
        extractionState: String = "pending",
        usedOCR: Bool = false,
        thumbnailPath: String? = nil,
        lastError: String? = nil
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
        self.lastIndexedAt = lastIndexedAt
        self.isMissing = isMissing
        self.extractionState = extractionState
        self.usedOCR = usedOCR
        self.thumbnailPath = thumbnailPath
        self.lastError = lastError
    }
}
