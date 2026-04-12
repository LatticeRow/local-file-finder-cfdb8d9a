# Local File Finder Implementation Handoff

## 1. Product Summary
Build a native iPhone app that lets users search inside the files they manage through the iOS Files ecosystem. The MVP should let a user add folders or individual files from Files, index supported content locally, run keyword search, and open results with useful snippets and location context.

The product promise is local-first document search with on-device OCR. File content must stay on device. Do not add a server, sync service, or external OCR API.

## 2. Product Reality and Platform Constraints
The idea says "all iPhone files," but the implementation must follow actual iOS rules.

Feasible for MVP:
- Search folders and files the user explicitly grants through the Files picker.
- Persist access to those locations with security-scoped bookmarks.
- Maintain a local index of extracted text, metadata, and snippets.
- Reindex authorized locations later, including from background opportunities when iOS allows it.

Not feasible for MVP:
- Crawling the entire device filesystem.
- Reading arbitrary files in other apps' sandboxes without user-granted access.
- Guaranteeing continuous real-time monitoring across every file provider.

User-facing copy should be explicit: "Search inside the folders and files you add from Files." Do not imply unrestricted device-wide access.

## 3. MVP Scope
### In scope
- Add folders or files from Files.
- Persist and restore authorized access across launches.
- Enumerate supported files inside those authorized locations.
- Extract text from plain text files and embedded-text PDFs.
- Run on-device OCR for images and scanned PDFs.
- Store extracted text and metadata locally.
- Search by keyword across indexed content.
- Show result rows with filename, location, snippet, and OCR indicator.
- Show indexing status, failures, and manual reindex controls.

### Explicitly out of scope for v1
- Semantic search or embeddings.
- Cloud sync.
- Collaboration or shared libraries.
- macOS, iPad, or Catalyst targets.
- Full editing workflows.
- Broad proprietary document format support without a reliable native extraction path.

## 4. Recommended Stack
Use Apple-native frameworks unless a measured blocker appears.

- Language: Swift
- UI: SwiftUI
- Local persistence: SwiftData
- PDF text extraction: PDFKit
- OCR: Vision text recognition
- File access: UIDocumentPickerViewController or SwiftUI `fileImporter`
- File type detection: UniformTypeIdentifiers
- Background refresh: BackgroundTasks
- Preview and thumbnails: QuickLook, QuickLookThumbnailing

Storage note:
- Start with SwiftData for metadata and extracted content.
- For very large text bodies, prefer chunked/page records instead of a single giant text blob.
- Only introduce a local SQLite FTS sidecar if profiling proves SwiftData string search is too slow.

## 5. Suggested Project Layout
Use a structure like this inside the Xcode project:

```text
LocalFileFinder/
  App/
    LocalFileFinderApp.swift
    AppContainer.swift
    RootView.swift
    AppState.swift
  Models/
    IndexedSource.swift
    IndexedFile.swift
    ExtractedContent.swift
    IndexingJob.swift
    SearchResultItem.swift
  Services/
    Bookmarks/
      SecurityScopedBookmarkManager.swift
      SourceAccessSession.swift
    Files/
      DocumentPickerCoordinator.swift
      FileEnumerationService.swift
      FileMetadataHasher.swift
    Extraction/
      ContentExtractionService.swift
      PlainTextExtractor.swift
      PDFTextExtractor.swift
      ImageOCRExtractor.swift
      PDFOCRExtractor.swift
    Indexing/
      IndexingCoordinator.swift
      IndexingProgressStore.swift
      BackgroundIndexScheduler.swift
    Search/
      SearchRepository.swift
      SearchRanker.swift
      SnippetBuilder.swift
    Preview/
      DocumentOpenCoordinator.swift
      ThumbnailService.swift
  Features/
    Onboarding/
      OnboardingView.swift
      OnboardingViewModel.swift
    Search/
      SearchView.swift
      SearchViewModel.swift
      SearchResultRow.swift
    Library/
      SourceLibraryView.swift
      SourceLibraryViewModel.swift
    Detail/
      DocumentDetailView.swift
      DocumentDetailViewModel.swift
    Settings/
      SettingsView.swift
  Utilities/
    Logger.swift
    UTType+SupportedTypes.swift
    String+Normalization.swift
    Date+Formatting.swift
  Tests/
    Unit/
    UI/
    Fixtures/
```

Important separation rule for the downstream agent:
- Keep file access, indexing, OCR, and search in `Services/`.
- Keep SwiftUI state and presentation in `Features/`.
- Do not bury file-system logic inside views.

## 6. Architecture Overview
### High-level flow
1. User adds one or more folders or files from Files.
2. The app creates security-scoped bookmarks and saves an `IndexedSource` record.
3. On launch or reindex, the app resolves bookmarks and starts access sessions.
4. The indexing coordinator enumerates files under each source.
5. Supported files are diffed against stored metadata.
6. New or changed files enter the extraction pipeline.
7. The extraction pipeline chooses plain text extraction, PDF text extraction, image OCR, or scanned-PDF OCR fallback.
8. The app stores normalized text, display snippets, and metadata in the local store.
9. Search queries run locally against the stored index.
10. Results render with filename, source path, snippet, file type, and OCR provenance.

### Core service responsibilities
#### `SecurityScopedBookmarkManager`
- Create bookmark data from user-selected URLs.
- Resolve bookmark data on launch.
- Detect stale bookmarks and mark a source as needing re-authorization.
- Wrap `startAccessingSecurityScopedResource()` / stop-access safely.

#### `DocumentPickerCoordinator`
- Present folder/file picker.
- Convert selections into source records.
- Limit the initial flow to standard Files providers.

#### `FileEnumerationService`
- Recursively enumerate authorized folders.
- Filter to supported UTTypes.
- Collect metadata: file name, relative path, display path, size, modification date, provider info.

#### `FileMetadataHasher`
- Optional helper for edge cases where modification date and size are not enough.
- Use only when needed because hashing large files is expensive.

#### `ContentExtractionService`
- Single entry point that chooses the right extractor by UTType.
- Return normalized text plus snippet/display content and extraction diagnostics.

#### `PlainTextExtractor`
- Support `.txt` and `.md` in MVP.
- Normalize whitespace and line breaks.

#### `PDFTextExtractor`
- Use PDFKit to extract embedded text page by page.
- Mark pages or whole documents for OCR fallback when text is empty or below a minimum threshold.

#### `ImageOCRExtractor`
- Use Vision for `.png`, `.jpg`, `.jpeg`, `.heic`.
- Normalize OCR output for search while preserving a readable preview.

#### `PDFOCRExtractor`
- Rasterize PDF pages that need OCR.
- Cap total OCR pages in MVP to control runtime.
- Persist OCR provenance for UI and diagnostics.

#### `IndexingCoordinator`
- Own full scan, source reindex, and incremental reindex.
- Use structured concurrency with bounded parallelism.
- Update persistent job progress and per-file failures.
- Never let one file failure abort the batch.

#### `SearchRepository`
- Execute local token-based queries over indexed metadata and extracted content.
- Support multi-token AND matching in MVP.
- Return a ranked `SearchResultItem` projection.

#### `SearchRanker`
First-pass ranking should be simple and deterministic:
- Exact filename token match: highest weight.
- Filename contains query token: high weight.
- Body contains all tokens: medium weight.
- More token hits near the snippet seed: small boost.
- Newer files: optional small boost.

#### `SnippetBuilder`
- Find the best local match position.
- Return a short snippet window around that match.
- Keep snippet generation out of the view layer.

#### `BackgroundIndexScheduler`
- Register a background refresh task.
- Schedule reindex opportunities for known sources.
- Degrade gracefully because iOS does not guarantee timing.

## 7. Data Model Notes
Use SwiftData models roughly like this.

### `IndexedSource`
Fields:
- `id: UUID`
- `displayName: String`
- `bookmarkData: Data`
- `sourceType: String` with values like `folder` or `file`
- `providerIdentifier: String?`
- `dateAdded: Date`
- `lastAuthorizedAt: Date?`
- `lastIndexedAt: Date?`
- `isAccessible: Bool`
- `lastError: String?`

### `IndexedFile`
Fields:
- `id: UUID`
- `sourceID`
- `fileName: String`
- `relativePath: String`
- `displayPath: String`
- `uti: String`
- `byteSize: Int64`
- `modificationDate: Date?`
- `contentHash: String?`
- `lastIndexedAt: Date?`
- `isMissing: Bool`
- `extractionState: String`
- `usedOCR: Bool`
- `thumbnailPath: String?`
- `lastError: String?`

### `ExtractedContent`
Prefer chunk- or page-level records rather than a single unbounded blob when content is large.

Fields:
- `id: UUID`
- `fileID`
- `chunkIndex: Int`
- `pageNumber: Int?`
- `fullTextNormalized: String`
- `fullTextPreview: String`
- `snippetSeedText: String?`
- `tokenCount: Int`
- `languageCode: String?`

### `IndexingJob`
Fields:
- `id: UUID`
- `scopeDescription: String`
- `startedAt: Date`
- `finishedAt: Date?`
- `status: String`
- `processedCount: Int`
- `successCount: Int`
- `failureCount: Int`
- `currentFileName: String?`

## 8. Search and Indexing Rules
### Supported file types in MVP
- `.txt`
- `.md`
- `.pdf`
- `.png`
- `.jpg`
- `.jpeg`
- `.heic`

### Deferred file types
Only attempt later if a reliable native extraction path is confirmed:
- `.rtf`
- Office documents
- Pages documents

### Incremental indexing rules
- If bookmark resolution fails, mark the source inaccessible and stop processing that source.
- If a file is gone, mark it missing and hide it from default results.
- If size and modification date are unchanged, skip reprocessing.
- If metadata changed or file is new, re-extract content.
- Only compute a content hash when metadata is insufficient.

### Text normalization rules
- Lowercase for indexed search text.
- Collapse repeated whitespace.
- Normalize line endings.
- Tokenize on non-alphanumeric boundaries for MVP.
- Preserve a readable preview string for UI display.

## 9. UI Plan
### Onboarding
Explain the access model clearly:
- Add folders or files from Files.
- Only added locations are searchable.
- Search stays on device.

Primary CTA:
- `Add Folder from Files`

Secondary CTA:
- `Add Individual Files`

### Search Home
Default post-onboarding screen.
Contains:
- Search field at the top.
- Indexing status summary.
- Query results list.
- Empty states for no sources, no indexed files, and no matches.

### Source Library
List authorized sources with:
- source name
- file count
- last indexed time
- accessibility/error state

Row actions:
- Reindex
- Re-authorize
- Remove source

### Result Row
Show:
- filename
- file type badge such as `PDF`, `IMG`, `TXT`
- breadcrumb/location
- snippet preview
- OCR badge when applicable

### Detail View
Show:
- file metadata
- larger snippet or page reference
- open/preview action
- source reference
- source/file reindex action if relevant

### Settings
Include:
- manual full reindex
- clear local index
- OCR behavior toggle if needed
- diagnostics summary: last run, failure count, indexed file count

## 10. Implementation Phases
### Phase 1: App shell and persistence
Deliverables:
- Xcode project
- SwiftUI navigation shell
- dependency container
- SwiftData models
- placeholder screens

### Phase 2: Source authorization
Deliverables:
- Files picker integration
- security-scoped bookmark persistence
- bookmark restore on launch
- source library UI with repair/remove actions

### Phase 3: Enumeration and text extraction
Deliverables:
- recursive enumeration
- supported-type filtering
- incremental diffing
- plain text extraction
- embedded PDF extraction

### Phase 4: OCR and search
Deliverables:
- Vision OCR for images
- scanned PDF OCR fallback
- search repository
- ranking
- snippet generation

### Phase 5: Product hardening
Deliverables:
- background reindex scheduling
- previews/thumbnails
- settings and maintenance tools
- tests and performance pass

## 11. Suggested File-by-File Build Order
The downstream agent should implement in this order and not skip ahead.

1. `App/LocalFileFinderApp.swift`
2. `App/AppContainer.swift`
3. persistence models in `Models/`
4. `Services/Bookmarks/SecurityScopedBookmarkManager.swift`
5. `Services/Files/DocumentPickerCoordinator.swift`
6. `Features/Onboarding/OnboardingView.swift`
7. `Features/Library/SourceLibraryView.swift`
8. `Services/Files/FileEnumerationService.swift`
9. `Services/Indexing/IndexingCoordinator.swift`
10. `Services/Extraction/PlainTextExtractor.swift`
11. `Services/Extraction/PDFTextExtractor.swift`
12. `Services/Extraction/ImageOCRExtractor.swift`
13. `Services/Extraction/PDFOCRExtractor.swift`
14. `Services/Search/SearchRepository.swift`
15. `Services/Search/SearchRanker.swift`
16. `Services/Search/SnippetBuilder.swift`
17. `Features/Search/SearchView.swift`
18. `Features/Detail/DocumentDetailView.swift`
19. `Services/Indexing/BackgroundIndexScheduler.swift`
20. tests and fixtures under `Tests/`

## 12. Test Strategy
Create fixtures in `Tests/Fixtures/`:
- text-only PDF
- scanned/image-only PDF
- screenshot with clear OCR text
- plain text note
- unsupported binary file
- larger PDF for profiling

### Required unit tests
- bookmark creation and restoration
- stale bookmark detection
- enumeration skips unsupported files
- incremental indexing skips unchanged files
- PDF extractor returns page text when available
- OCR fallback triggers when PDF text is missing
- ranking prefers filename hits over body hits
- snippet builder returns surrounding text correctly

### Required UI tests
- onboarding shows source add flow
- adding a source leads to a searchable state
- entering a query shows at least one result row with snippet

### Manual validation
- mixed iCloud Drive folder
- at least one third-party provider if available
- relaunch behavior after bookmark restore
- image-heavy folder indexing performance
- background refresh behavior after scheduling

## 13. Acceptance Criteria
The implementation is acceptable when all of the following are true:
- A user can add folders or files from Files and the app remembers them across launches.
- The app indexes supported text files, PDFs, and common image formats locally.
- The app performs on-device OCR for images and scanned PDFs.
- Search returns useful keyword matches with filename, location, and snippet.
- The app clearly shows indexing state and explains failures or unsupported files.
- Reindexing avoids unnecessary repeat work for unchanged files.
- No file content leaves the device.
- Service tests and at least one UI flow test pass.

## 14. Risks and Mitigations
### Sandbox limitations
Mitigation:
- Build only around user-granted sources.
- Make the scope explicit in UI copy and marketing.
- Add repair flows for stale bookmarks.

### OCR latency and battery cost
Mitigation:
- Use bounded concurrency.
- Cap OCR pages for very large PDFs in MVP.
- Persist OCR results and avoid redoing unchanged work.
- Allow cancellation or graceful interruption.

### Search performance on large text blobs
Mitigation:
- Store extracted text in chunks/pages.
- Start with SwiftData.
- Measure before adding a local FTS sidecar.

### Provider inconsistency
Mitigation:
- Test against iCloud Drive first.
- Track provider identifiers.
- Use defensive file coordination and visible retry states.

### Native competition
Mitigation:
- Differentiate with snippets, explicit OCR handling, source management, and privacy-first local indexing.

## 15. Notes for the Weaker Downstream Agent
- This is a native iPhone app. Do not scaffold a web frontend or backend.
- Do not promise unrestricted access to all device files.
- Keep the indexing pipeline protocol-driven and testable.
- Keep UI code separate from file logic.
- Prefer a smaller, reliable support matrix over broad but brittle document support.
- If SwiftData search becomes a real measured bottleneck, document the problem first, then add a local FTS sidecar.
- One bad file must never break the whole indexing job.

## 16. Execution Lane and Handoff Rules
Use a Codex-first Mac execution lane from the start.

Requirements for each implementation task:
- preferred agent: `codex`
- execution target: `mac_ios`
- required capabilities must include `codex.exec`, `ios.build`, `ios.test`, and `ios.simulator`
- use git branch handoff so the Mac worker can pull the branch and run the app locally

The downstream agent should complete tasks in order, commit cleanly per phase or task cluster, and verify simulator builds after every meaningful service or UI milestone.