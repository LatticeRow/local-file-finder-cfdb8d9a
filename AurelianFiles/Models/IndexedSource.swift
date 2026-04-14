import Foundation
import SwiftData

@Model
final class IndexedSource {
    enum SourceType: String, CaseIterable, Codable {
        case folder
        case file
    }

    @Attribute(.unique) var id: UUID
    var displayName: String
    @Attribute(.externalStorage) var bookmarkData: Data
    var sourceType: String
    var providerIdentifier: String?
    var dateAdded: Date
    var lastAuthorizedAt: Date?
    var lastIndexedAt: Date?
    var lastBookmarkRefreshAt: Date?
    var isAccessible: Bool
    var requiresReauthorization: Bool
    var lastErrorMessage: String?
    var lastErrorDomain: String?
    var lastErrorCode: Int?
    var lastErrorAt: Date?
    @Relationship(deleteRule: .cascade) var files: [IndexedFile]

    init(
        id: UUID = UUID(),
        displayName: String,
        bookmarkData: Data = Data(),
        sourceType: String,
        providerIdentifier: String? = nil,
        dateAdded: Date = .now,
        lastAuthorizedAt: Date? = nil,
        lastIndexedAt: Date? = nil,
        lastBookmarkRefreshAt: Date? = nil,
        isAccessible: Bool = true,
        requiresReauthorization: Bool = false,
        lastErrorMessage: String? = nil,
        lastErrorDomain: String? = nil,
        lastErrorCode: Int? = nil,
        lastErrorAt: Date? = nil,
        files: [IndexedFile] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.bookmarkData = bookmarkData
        self.sourceType = sourceType
        self.providerIdentifier = providerIdentifier
        self.dateAdded = dateAdded
        self.lastAuthorizedAt = lastAuthorizedAt
        self.lastIndexedAt = lastIndexedAt
        self.lastBookmarkRefreshAt = lastBookmarkRefreshAt
        self.isAccessible = isAccessible
        self.requiresReauthorization = requiresReauthorization
        self.lastErrorMessage = lastErrorMessage
        self.lastErrorDomain = lastErrorDomain
        self.lastErrorCode = lastErrorCode
        self.lastErrorAt = lastErrorAt
        self.files = files
    }
}

extension IndexedSource {
    var resolvedSourceType: SourceType {
        SourceType(rawValue: sourceType) ?? .file
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
