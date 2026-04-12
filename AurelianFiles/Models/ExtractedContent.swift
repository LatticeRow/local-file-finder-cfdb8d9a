import Foundation
import SwiftData

@Model
final class ExtractedContent {
    @Attribute(.unique) var id: UUID
    var fileID: UUID
    var chunkIndex: Int
    var pageNumber: Int?
    var fullTextNormalized: String
    var fullTextPreview: String
    var snippetSeedText: String?
    var tokenCount: Int
    var languageCode: String?

    init(
        id: UUID = UUID(),
        fileID: UUID,
        chunkIndex: Int = 0,
        pageNumber: Int? = nil,
        fullTextNormalized: String,
        fullTextPreview: String,
        snippetSeedText: String? = nil,
        tokenCount: Int = 0,
        languageCode: String? = nil
    ) {
        self.id = id
        self.fileID = fileID
        self.chunkIndex = chunkIndex
        self.pageNumber = pageNumber
        self.fullTextNormalized = fullTextNormalized
        self.fullTextPreview = fullTextPreview
        self.snippetSeedText = snippetSeedText
        self.tokenCount = tokenCount
        self.languageCode = languageCode
    }
}
