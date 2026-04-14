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
    ) -> [EnumeratedFile] {
        logger.info("Enumerating files for \(sourceName)")

        if sourceType == "file" {
            return coordinatedRead(at: sourceURL) { coordinatedURL in
                enumeratedFile(
                    at: coordinatedURL,
                    sourceID: sourceID,
                    rootURL: coordinatedURL.deletingLastPathComponent()
                ).map { [$0] } ?? []
            } ?? []
        }

        let files = recursivelyEnumerateFiles(
            at: sourceURL,
            sourceID: sourceID,
            rootURL: sourceURL
        )

        return files.sorted {
            $0.relativePath.localizedCaseInsensitiveCompare($1.relativePath) == .orderedAscending
        }
    }

    private func enumeratedFile(at fileURL: URL, sourceID: UUID, rootURL: URL) -> EnumeratedFile? {
        let values = try? fileURL.resourceValues(forKeys: [
            .isRegularFileKey,
            .contentTypeKey,
            .fileSizeKey,
            .contentModificationDateKey,
        ])

        guard values?.isRegularFile == true else {
            return nil
        }

        let uti = values?.contentType?.identifier
            ?? UTType(filenameExtension: fileURL.pathExtension)?.identifier
            ?? "public.data"
        let relativePath = relativePathForFile(at: fileURL, rootURL: rootURL)

        return EnumeratedFile(
            sourceID: sourceID,
            fileURL: fileURL,
            fileName: fileURL.lastPathComponent,
            relativePath: relativePath,
            displayPath: relativePath,
            uti: uti,
            byteSize: Int64(values?.fileSize ?? 0),
            modificationDate: values?.contentModificationDate
        )
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
    ) -> [EnumeratedFile] {
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

            for childURL in childURLs {
                files.append(contentsOf: enumerateChild(
                    at: childURL,
                    sourceID: sourceID,
                    rootURL: rootURL
                ))
            }

            return files
        } ?? []
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
    ) -> [EnumeratedFile] {
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
            return []
        }

        if values.isHidden == true {
            return []
        }

        if values.isRegularFile == true {
            return enumeratedFile(at: childURL, sourceID: sourceID, rootURL: rootURL).map { [$0] } ?? []
        }

        if values.isDirectory == true, shouldDescendIntoDirectory(at: childURL, values: values) {
            return recursivelyEnumerateFiles(
                at: childURL,
                sourceID: sourceID,
                rootURL: rootURL
            )
        }

        return []
    }
}
