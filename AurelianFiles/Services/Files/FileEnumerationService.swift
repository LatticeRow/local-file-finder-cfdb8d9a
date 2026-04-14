import Foundation
import UniformTypeIdentifiers

struct EnumeratedFile: Identifiable, Hashable {
    let id = UUID()
    let sourceID: UUID
    let fileURL: URL
    let fileName: String
    let relativePath: String
    let displayPath: String
    let uti: String
    let byteSize: Int64
    let modificationDate: Date?
}

struct FileEnumerationResult {
    let files: [EnumeratedFile]
    let unsupportedCount: Int
}

final class FileEnumerationService {
    private let logger: AppLogger

    init(logger: AppLogger) {
        self.logger = logger
    }

    func enumerateVisibleFiles(
        at sourceURL: URL,
        sourceID: UUID,
        sourceName: String,
        sourceType: String
    ) -> FileEnumerationResult {
        logger.info("Enumerating files for \(sourceName)")

        if sourceType == "file" {
            return coordinatedRead(at: sourceURL) { coordinatedURL in
                let outcome = enumeratedFile(
                    at: coordinatedURL,
                    sourceID: sourceID,
                    rootURL: coordinatedURL.deletingLastPathComponent()
                )

                switch outcome {
                case .included(let file):
                    return FileEnumerationResult(files: [file], unsupportedCount: 0)
                case .unsupported:
                    return FileEnumerationResult(files: [], unsupportedCount: 1)
                case .ignored:
                    return FileEnumerationResult(files: [], unsupportedCount: 0)
                }
            } ?? FileEnumerationResult(files: [], unsupportedCount: 0)
        }

        let result = recursivelyEnumerateFiles(
            at: sourceURL,
            sourceID: sourceID,
            rootURL: sourceURL
        )

        let sortedFiles = result.files.sorted {
            $0.relativePath.localizedCaseInsensitiveCompare($1.relativePath) == .orderedAscending
        }

        if result.unsupportedCount > 0 {
            logger.info("Skipped \(result.unsupportedCount) unsupported files while scanning \(sourceName)")
        }

        return FileEnumerationResult(files: sortedFiles, unsupportedCount: result.unsupportedCount)
    }

    private enum EnumeratedItem {
        case included(EnumeratedFile)
        case unsupported
        case ignored
    }

    private func enumeratedFile(at fileURL: URL, sourceID: UUID, rootURL: URL) -> EnumeratedItem {
        let values = try? fileURL.resourceValues(forKeys: [
            .isRegularFileKey,
            .contentTypeKey,
            .fileSizeKey,
            .contentModificationDateKey,
        ])

        guard values?.isRegularFile == true else {
            return .ignored
        }

        guard let uti = SupportedSearchContentTypes.supportedIdentifier(
            for: fileURL,
            declaredType: values?.contentType
        ) else {
            logger.info("Skipping unsupported file \(fileURL.lastPathComponent)")
            return .unsupported
        }

        let relativePath = relativePathForFile(at: fileURL, rootURL: rootURL)

        return .included(EnumeratedFile(
            sourceID: sourceID,
            fileURL: fileURL,
            fileName: fileURL.lastPathComponent,
            relativePath: relativePath,
            displayPath: relativePath,
            uti: uti,
            byteSize: Int64(values?.fileSize ?? 0),
            modificationDate: values?.contentModificationDate
        ))
    }

    private func relativePathForFile(at fileURL: URL, rootURL: URL) -> String {
        let rootPath = rootURL.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path

        guard filePath.hasPrefix(rootPath) else {
            return fileURL.lastPathComponent
        }

        let trimmed = filePath.dropFirst(rootPath.count).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmed.isEmpty ? fileURL.lastPathComponent : trimmed
    }

    private func recursivelyEnumerateFiles(
        at directoryURL: URL,
        sourceID: UUID,
        rootURL: URL
    ) -> FileEnumerationResult {
        coordinatedRead(at: directoryURL) { coordinatedDirectoryURL in
            let childURLs = (try? FileManager.default.contentsOfDirectory(
                at: coordinatedDirectoryURL,
                includingPropertiesForKeys: [
                    .isDirectoryKey,
                    .isRegularFileKey,
                    .isPackageKey,
                    .isHiddenKey,
                    .contentTypeKey,
                    .fileSizeKey,
                    .contentModificationDateKey,
                ],
                options: [.skipsHiddenFiles]
            )) ?? []

            var files: [EnumeratedFile] = []
            var unsupportedCount = 0

            for childURL in childURLs {
                let childResult = enumerateChild(
                    at: childURL,
                    sourceID: sourceID,
                    rootURL: rootURL
                )
                files.append(contentsOf: childResult.files)
                unsupportedCount += childResult.unsupportedCount
            }

            return FileEnumerationResult(files: files, unsupportedCount: unsupportedCount)
        } ?? FileEnumerationResult(files: [], unsupportedCount: 0)
    }

    private func coordinatedRead<T>(at url: URL, body: (URL) -> T) -> T? {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var result: T?

        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            result = body(coordinatedURL)
        }

        if coordinationError != nil {
            logger.info("File coordination failed for \(url.lastPathComponent)")
        }

        return result
    }

    private func shouldDescendIntoDirectory(
        at directoryURL: URL,
        values: URLResourceValues
    ) -> Bool {
        if values.isPackage != true {
            return true
        }

        // Files app app-containers such as "Chrome" can surface as packages when
        // traversed from "On My iPhone", but they still need recursive indexing.
        return directoryURL.pathExtension.isEmpty
    }

    private func enumerateChild(
        at childURL: URL,
        sourceID: UUID,
        rootURL: URL
    ) -> FileEnumerationResult {
        let didAccess = childURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                childURL.stopAccessingSecurityScopedResource()
            }
        }

        guard let values = try? childURL.resourceValues(forKeys: [
            .isDirectoryKey,
            .isRegularFileKey,
            .isPackageKey,
            .isHiddenKey,
        ]) else {
            return FileEnumerationResult(files: [], unsupportedCount: 0)
        }

        if values.isHidden == true {
            return FileEnumerationResult(files: [], unsupportedCount: 0)
        }

        if values.isRegularFile == true {
            let outcome = enumeratedFile(at: childURL, sourceID: sourceID, rootURL: rootURL)

            switch outcome {
            case .included(let file):
                return FileEnumerationResult(files: [file], unsupportedCount: 0)
            case .unsupported:
                return FileEnumerationResult(files: [], unsupportedCount: 1)
            case .ignored:
                return FileEnumerationResult(files: [], unsupportedCount: 0)
            }
        }

        if values.isDirectory == true, shouldDescendIntoDirectory(at: childURL, values: values) {
            return recursivelyEnumerateFiles(
                at: childURL,
                sourceID: sourceID,
                rootURL: rootURL
            )
        }

        return FileEnumerationResult(files: [], unsupportedCount: 0)
    }
}
