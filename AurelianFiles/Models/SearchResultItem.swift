import Foundation

struct SearchResultItem: Identifiable, Hashable {
    let id: UUID
    let title: String
    let location: String
    let snippet: String
    let fileType: String
    let usedOCR: Bool

    init(
        id: UUID = UUID(),
        title: String,
        location: String,
        snippet: String,
        fileType: String,
        usedOCR: Bool = false
    ) {
        self.id = id
        self.title = title
        self.location = location
        self.snippet = snippet
        self.fileType = fileType
        self.usedOCR = usedOCR
    }
}
