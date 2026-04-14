import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import CryptoKit
import UIKit

struct OnboardingView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.modelContext) private var modelContext

    @State private var activePickerMode: PickerMode?
    @State private var importErrorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Search only the folders and files you add from Files.")
                .font(.title2.weight(.semibold))
                .foregroundStyle(AppTheme.primaryText)

            Text("Aurelian Files keeps search on this iPhone. Added folders include their subfolders.")
                .foregroundStyle(AppTheme.secondaryText)

            VStack(alignment: .leading, spacing: 12) {
                Label("Add folders or individual files from Files", systemImage: "folder.badge.plus")
                Label("Keep your search data on this iPhone", systemImage: "lock.shield")
                Label("Search file names and document text", systemImage: "doc.text.magnifyingglass")
            }
            .foregroundStyle(AppTheme.primaryText)

            HStack(spacing: 12) {
                Button("Add Folder from Files") {
                    activePickerMode = .folder
                }
                    .buttonStyle(.borderedProminent)

                Button("Add Individual Files") {
                    activePickerMode = .file
                }
                    .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        )
        .sheet(item: $activePickerMode) { mode in
            SecurityScopedDocumentPicker(
                allowedContentTypes: mode.allowedContentTypes(fileContentTypes: fileContentTypes),
                allowsMultipleSelection: true
            ) { result in
                handleImport(result, sourceType: mode.sourceType)
            }
        }
        .alert(
            "Couldn't import selection",
            isPresented: Binding(
                get: { importErrorMessage != nil },
                set: { if !$0 { importErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importErrorMessage ?? "Unknown error.")
        }
    }

    private var fileContentTypes: [UTType] {
        container.documentPickerCoordinator.supportedContentTypes.filter { $0 != .folder }
    }

    private func handleImport(_ result: Result<[URL], Error>, sourceType: String) {
        activePickerMode = nil

        do {
            let urls = try result.get()
            let importedSources = try persistImportedSources(urls, sourceType: sourceType)
            if !importedSources.isEmpty {
                container.indexingCoordinator.runReindexImportedSources(importedSources)
                container.appState.selectedTab = .search
            }
        } catch {
            importErrorMessage = "Try choosing the folder or file again."
        }
    }

    private func persistImportedSources(_ urls: [URL], sourceType: String) throws -> [ImportedSource] {
        let existingSources = try modelContext.fetch(FetchDescriptor<IndexedSource>())
        let existingIdentifiers = Set(existingSources.compactMap(\.providerIdentifier))

        var importedSources: [ImportedSource] = []

        for url in urls {
            let providerIdentifier = sourceIdentifier(for: url, sourceType: sourceType)
            guard !existingIdentifiers.contains(providerIdentifier) else {
                continue
            }

            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let bookmarkData = try container.bookmarkManager.createBookmark(for: url)
            let source = IndexedSource(
                displayName: url.lastPathComponent,
                bookmarkData: bookmarkData,
                sourceType: sourceType,
                providerIdentifier: providerIdentifier,
                lastAuthorizedAt: .now,
                isAccessible: true
            )
            modelContext.insert(source)
            importedSources.append(ImportedSource(id: source.id, url: url))
        }

        if !importedSources.isEmpty {
            try modelContext.save()
        }

        return importedSources
    }

    private func sourceIdentifier(for url: URL, sourceType: String) -> String {
        let input = "\(sourceType)|\(url.absoluteString)"
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

struct ImportedSource: Hashable {
    let id: UUID
    let url: URL
}

private enum PickerMode: String, Identifiable {
    case folder
    case file

    var id: String { rawValue }

    var sourceType: String { rawValue }

    func allowedContentTypes(fileContentTypes: [UTType]) -> [UTType] {
        switch self {
        case .folder:
            return [.folder]
        case .file:
            return fileContentTypes
        }
    }
}

private struct SecurityScopedDocumentPicker: UIViewControllerRepresentable {
    let allowedContentTypes: [UTType]
    let allowsMultipleSelection: Bool
    let onComplete: (Result<[URL], Error>) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let controller = UIDocumentPickerViewController(
            forOpeningContentTypes: allowedContentTypes,
            asCopy: false
        )
        controller.delegate = context.coordinator
        controller.allowsMultipleSelection = allowsMultipleSelection
        return controller
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onComplete: (Result<[URL], Error>) -> Void

        init(onComplete: @escaping (Result<[URL], Error>) -> Void) {
            self.onComplete = onComplete
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onComplete(.success(urls))
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onComplete(.success([]))
        }
    }
}

#Preview {
    OnboardingView()
        .padding()
        .background(AppTheme.background)
        .environment(AppContainer.preview())
        .modelContainer(AppContainer.makeModelContainer(inMemoryOnly: true))
        .preferredColorScheme(.dark)
}
