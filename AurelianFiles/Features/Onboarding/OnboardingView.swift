import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit

struct OnboardingView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.modelContext) private var modelContext

    @State private var activePickerMode: SourcePickerMode?
    @State private var importErrorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Search what you add from Files.")
                .font(.title2.weight(.semibold))
                .foregroundStyle(AppTheme.primaryText)

            Text("Add folders or files, then search them here.")
                .foregroundStyle(AppTheme.secondaryText)

            VStack(alignment: .leading, spacing: 12) {
                Label("Add folders or files", systemImage: "folder.badge.plus")
                Label("Search stays on this iPhone", systemImage: "lock.shield")
            }
            .foregroundStyle(AppTheme.primaryText)

            HStack(spacing: 12) {
                Button("Add Folder") {
                    activePickerMode = .folder
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityIdentifier("onboarding.add-folder")

                Button("Add Files") {
                    activePickerMode = .file
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("onboarding.add-files")
            }
        }
        .padding(20)
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
        container.documentPickerCoordinator.supportedFileContentTypes
    }

    private func handleImport(_ result: Result<[URL], Error>, sourceType: IndexedSource.SourceType) {
        activePickerMode = nil

        do {
            let urls = try result.get()
            guard !urls.isEmpty else {
                return
            }

            let importedSources = try container.documentPickerCoordinator.importSelections(
                urls,
                as: sourceType,
                into: modelContext
            )
            if !importedSources.isEmpty {
                container.indexingCoordinator.runReindexImportedSources(importedSources)
                container.appState.selectedTab = .search
            }
        } catch {
            importErrorMessage = error.localizedDescription
        }
    }
}

enum SourcePickerMode: String, Identifiable {
    case folder
    case file

    var id: String { rawValue }

    var sourceType: IndexedSource.SourceType {
        switch self {
        case .folder:
            return .folder
        case .file:
            return .file
        }
    }

    func allowedContentTypes(fileContentTypes: [UTType]) -> [UTType] {
        switch self {
        case .folder:
            return [.folder]
        case .file:
            return fileContentTypes
        }
    }
}

struct SecurityScopedDocumentPicker: UIViewControllerRepresentable {
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
