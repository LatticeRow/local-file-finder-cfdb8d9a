import Foundation
import SwiftData

@Model
final class IndexedSource {
    @Attribute(.unique) var id: UUID
    var displayName: String
    var bookmarkData: Data
    var sourceType: String
    var providerIdentifier: String?
    var dateAdded: Date
    var lastAuthorizedAt: Date?
    var lastIndexedAt: Date?
    var isAccessible: Bool
    var lastError: String?

    init(
        id: UUID = UUID(),
        displayName: String,
        bookmarkData: Data = Data(),
        sourceType: String,
        providerIdentifier: String? = nil,
        dateAdded: Date = .now,
        lastAuthorizedAt: Date? = nil,
        lastIndexedAt: Date? = nil,
        isAccessible: Bool = true,
        lastError: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.bookmarkData = bookmarkData
        self.sourceType = sourceType
        self.providerIdentifier = providerIdentifier
        self.dateAdded = dateAdded
        self.lastAuthorizedAt = lastAuthorizedAt
        self.lastIndexedAt = lastIndexedAt
        self.isAccessible = isAccessible
        self.lastError = lastError
    }
}
