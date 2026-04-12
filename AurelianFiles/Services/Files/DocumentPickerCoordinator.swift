import Foundation
import UniformTypeIdentifiers

final class DocumentPickerCoordinator {
    let supportedContentTypes: [UTType] = [
        .folder,
        .plainText,
        .pdf,
        .png,
        .jpeg,
        .heic,
    ]
}
